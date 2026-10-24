package ratelimit

import (
	"context"
	"errors"
	"io"
	"strconv"
	"time"
)

type Limited struct{ RetryAfter int }

func (e *Limited) Error() string { return "shared request rate limited" }

// ReadBody reserves before every read, and settles n even when ReadFull also
// returns EOF/cancellation. Only this bounded private buffer reaches decoders.
// Unknown settlement remains conservatively reserved and stops the transfer.
func (c *Controller) ReadBody(ctx context.Context, subject string, reader io.Reader, maximum, expected int64) ([]byte, error) {
	if maximum < 1 || maximum > 16*1024*1024 {
		return nil, ErrUnavailable
	}
	transfer := randomDigest()
	if transfer == "" {
		return nil, ErrUnavailable
	}
	var data []byte
	expires := time.Now().Add(c.ReadWindow())
	enforced := c.TransferEnforced()
	if expected == 0 {
		d, err := c.Admit(ctx, subject, []Charge{{"upload.attempt", 1}}, Proof{})
		if err != nil {
			return nil, err
		}
		if !d.Allowed {
			return nil, &Limited{d.RetryAfter}
		}
		return data, nil
	}
	for sequence := 0; int64(len(data)) <= maximum; sequence++ {
		if enforced && !time.Now().Before(expires) {
			return nil, ErrUnavailable
		}
		want := int64(65536)
		if left := maximum + 1 - int64(len(data)); left < want {
			want = left
		}
		if expected >= 0 && expected <= maximum {
			if left := expected - int64(len(data)); left < want {
				want = left
			}
			if want == 0 {
				return data, nil
			}
		}
		id := transfer + ":" + strconv.Itoa(sequence)
		var decision Decision
		var err error
		if sequence == 0 {
			decision, err = c.BeginTransfer(ctx, subject, id, want)
		} else {
			decision, err = c.ReserveChunk(ctx, subject, id, want)
		}
		if err != nil {
			return nil, err
		}
		if !decision.Allowed {
			return nil, &Limited{decision.RetryAfter}
		}
		reserved := decision.Reserved
		if reserved < 1 || reserved > want {
			return nil, ErrUnavailable
		}
		chunk := make([]byte, int(reserved))
		n, readErr := io.ReadFull(reader, chunk)
		// Cancellation of a client connection cannot turn received n into zero.
		if err = c.SettleChunk(context.WithoutCancel(ctx), subject, id, int64(n)); err != nil {
			return nil, err
		}
		if enforced && !time.Now().Before(expires) {
			return nil, ErrUnavailable
		}
		data = append(data, chunk[:n]...)
		if readErr != nil {
			if errors.Is(readErr, io.EOF) || errors.Is(readErr, io.ErrUnexpectedEOF) {
				return data, nil
			}
			return nil, readErr
		}
		if err = ctx.Err(); err != nil {
			return nil, err
		}
	}
	return data, nil
}
