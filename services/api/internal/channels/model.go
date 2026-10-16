package channels

import (
	"context"
	"errors"

	"github.com/google/uuid"
)

var ErrInvalidCatalog = errors.New("channel catalog is incomplete or invalid")

// Channel is the server-owned business record used by the directory API.
type Channel struct {
	ID               uuid.UUID
	Code             string
	Name             string
	InitiallyVisible bool
	DisplayOrder     int
}

type Repository interface {
	List(ctx context.Context) ([]Channel, error)
}
