package comments

import (
	"sort"
	"time"
)

const (
	MainPinnedCount  = 10
	ReplyPinnedCount = 5
	DefaultPageSize  = 50
	MaxPageSize      = 50
)

type OrderKind string

const (
	MainComments OrderKind = "MAIN"
	Replies      OrderKind = "REPLIES"
)

// OrderItem contains only the inputs needed to freeze a reading order. The
// service must supply items from one authorized post or one authorized root.
type OrderItem struct {
	CommentID   string
	LikeCount   int64
	PublishedAt time.Time
}

// Snapshot is a pure immutable order. Production pagination still needs a
// scoped authenticated cursor and a current authorization/deletion check.
// New comments enter a fresh snapshot only on re-entry or reopening the area.
type Snapshot struct {
	kind   OrderKind
	pinned int
	items  []OrderItem
}

type SortMode string

const (
	Relevant  SortMode = "relevant"
	Recent    SortMode = "recent"
	MostLiked SortMode = "likes"
)

func (m SortMode) Valid() bool { return m == "" || m == Relevant || m == Recent || m == MostLiked }

func NewSnapshot(kind OrderKind, items []OrderItem) (Snapshot, error) {
	return NewSortedSnapshot(kind, items, Relevant)
}

// Sorting is captured before pagination; subsequent likes never move rows.
func NewSortedSnapshot(kind OrderKind, items []OrderItem, mode SortMode) (Snapshot, error) {
	if !mode.Valid() {
		return Snapshot{}, ErrInvalid
	}
	pinned := MainPinnedCount
	if kind == Replies {
		pinned = ReplyPinnedCount
	} else if kind != MainComments {
		return Snapshot{}, ErrInvalid
	}
	seen := make(map[string]bool, len(items))
	copyItems := append([]OrderItem(nil), items...)
	for i := range copyItems {
		item := &copyItems[i]
		if !validID(item.CommentID) || seen[item.CommentID] || item.LikeCount < 0 || item.PublishedAt.IsZero() {
			return Snapshot{}, ErrInvalid
		}
		seen[item.CommentID] = true
		item.PublishedAt = item.PublishedAt.UTC()
	}
	chronological := func(a, b OrderItem) bool {
		if !a.PublishedAt.Equal(b.PublishedAt) {
			return a.PublishedAt.Before(b.PublishedAt)
		}
		// Canonical UUID text ordering matches raw-byte lexicographic ordering.
		return a.CommentID < b.CommentID
	}
	sort.Slice(copyItems, func(i, j int) bool {
		if copyItems[i].LikeCount != copyItems[j].LikeCount {
			return copyItems[i].LikeCount > copyItems[j].LikeCount
		}
		return chronological(copyItems[i], copyItems[j])
	})
	if pinned > len(copyItems) {
		pinned = len(copyItems)
	}
	if mode == Recent {
		sort.Slice(copyItems, func(i, j int) bool {
			if !copyItems[i].PublishedAt.Equal(copyItems[j].PublishedAt) {
				return copyItems[i].PublishedAt.After(copyItems[j].PublishedAt)
			}
			return copyItems[i].CommentID < copyItems[j].CommentID
		})
	} else if mode != MostLiked {
		sort.Slice(copyItems[pinned:], func(i, j int) bool {
			return chronological(copyItems[pinned+i], copyItems[pinned+j])
		})
	}
	return Snapshot{kind: kind, pinned: pinned, items: copyItems}, nil
}

type Page struct {
	Items      []OrderItem
	NextOffset *int
}

func (s Snapshot) Page(offset, limit int) (Page, error) {
	if s.kind != MainComments && s.kind != Replies {
		return Page{}, ErrInvalid
	}
	if limit == 0 {
		limit = DefaultPageSize
	}
	if offset < 0 || offset > len(s.items) || limit < 1 || limit > MaxPageSize {
		return Page{}, ErrPage
	}
	end := offset + min(limit, len(s.items)-offset)
	p := Page{Items: append([]OrderItem{}, s.items[offset:end]...)}
	if end < len(s.items) {
		next := end
		p.NextOffset = &next
	}
	return p, nil
}

// Preview returns exactly the default per-root five (or main top ten), not a
// different order. Main top ten are never a limit on the main comment list.
func (s Snapshot) Preview() []OrderItem {
	return append([]OrderItem{}, s.items[:s.pinned]...)
}

func (s Snapshot) Len() int { return len(s.items) }

// WithLikeCount updates a number without moving the item or selecting new pins.
func (s Snapshot) WithLikeCount(commentID string, count int64) (Snapshot, error) {
	if count < 0 || !validID(commentID) {
		return Snapshot{}, ErrInvalid
	}
	s.items = append([]OrderItem(nil), s.items...)
	for i := range s.items {
		if s.items[i].CommentID == commentID {
			s.items[i].LikeCount = count
			return s, nil
		}
	}
	return Snapshot{}, ErrInvalid
}

// Without removes content already known to be deleted/inaccessible, preserving
// all remaining positions. It does not promote a replacement into pinned slots.
func (s Snapshot) Without(commentIDs ...string) Snapshot {
	removed := make(map[string]bool, len(commentIDs))
	for _, id := range commentIDs {
		removed[id] = true
	}
	items := make([]OrderItem, 0, len(s.items))
	pinned := 0
	for i, item := range s.items {
		if !removed[item.CommentID] {
			items = append(items, item)
			if i < s.pinned {
				pinned++
			}
		}
	}
	s.items, s.pinned = items, pinned
	return s
}
