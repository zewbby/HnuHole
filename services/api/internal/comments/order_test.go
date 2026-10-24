package comments

import (
	"errors"
	"reflect"
	"testing"
	"time"
)

func itemIDs(items []OrderItem) []string {
	ids := make([]string, len(items))
	for i, item := range items {
		ids[i] = item.CommentID
	}
	return ids
}

func TestSegmentedRankingKeepsRemainderChronological(t *testing.T) {
	items := make([]OrderItem, 13)
	for i := range items {
		items[i] = OrderItem{CommentID: resourceID(i + 1), PublishedAt: testAt.Add(time.Duration(i) * time.Second), LikeCount: int64(i)}
	}
	for _, spec := range []struct {
		kind OrderKind
		pins int
	}{{MainComments, 10}, {Replies, 5}} {
		snapshot, err := NewSnapshot(spec.kind, items)
		if err != nil {
			t.Fatal(err)
		}
		page, err := snapshot.Page(0, 0)
		if err != nil || len(page.Items) != len(items) || len(snapshot.Preview()) != spec.pins {
			t.Fatal("ranking limited total comment count", err)
		}
		want := make([]string, 0, len(items))
		for n := len(items); n > len(items)-spec.pins; n-- {
			want = append(want, resourceID(n))
		}
		for n := 1; n <= len(items)-spec.pins; n++ {
			want = append(want, resourceID(n))
		}
		if !reflect.DeepEqual(itemIDs(page.Items), want) {
			t.Fatal("top segment or chronological remainder changed", itemIDs(page.Items), want)
		}
	}
}

func TestTieBoundaryUsesTimeThenCanonicalUUID(t *testing.T) {
	items := []OrderItem{
		{resourceID(8), 1, testAt.Add(time.Second)},
		{resourceID(7), 1, testAt},
		{resourceID(6), 1, testAt},
		{resourceID(5), 1, testAt},
		{resourceID(4), 1, testAt},
		{resourceID(3), 1, testAt},
		{resourceID(2), 1, testAt},
		{resourceID(1), 1, testAt},
	}
	snapshot, err := NewSnapshot(Replies, items)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(itemIDs(snapshot.Preview()), []string{resourceID(1), resourceID(2), resourceID(3), resourceID(4), resourceID(5)}) {
		t.Fatal("tie boundary is unstable")
	}
	page, _ := snapshot.Page(0, 0)
	if !reflect.DeepEqual(itemIDs(page.Items), []string{resourceID(1), resourceID(2), resourceID(3), resourceID(4), resourceID(5), resourceID(6), resourceID(7), resourceID(8)}) {
		t.Fatal("tie remainder is unstable")
	}
}

func TestSnapshotPagesDoNotReorderOnLikesOrCallerMutation(t *testing.T) {
	items := make([]OrderItem, 103)
	for i := range items {
		items[i] = OrderItem{CommentID: resourceID(i + 1), PublishedAt: testAt.Add(time.Duration(i) * time.Second)}
	}
	snapshot, err := NewSnapshot(MainComments, items)
	if err != nil {
		t.Fatal(err)
	}
	items[0].CommentID = resourceID(999)
	updated, err := snapshot.WithLikeCount(resourceID(103), 9999)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for offset := 0; ; {
		page, err := updated.Page(offset, 0)
		if err != nil || len(page.Items) > DefaultPageSize {
			t.Fatal("invalid page", err)
		}
		got = append(got, itemIDs(page.Items)...)
		page.Items[0].CommentID = resourceID(998)
		if page.NextOffset == nil {
			break
		}
		offset = *page.NextOffset
	}
	want := make([]string, len(items))
	for i := range want {
		want[i] = resourceID(i + 1)
	}
	if !reflect.DeepEqual(got, want) || len(updated.Preview()) != 10 {
		t.Fatal("likes reselected pins or pagination skipped/duplicated content")
	}
	page, _ := snapshot.Page(100, 0)
	if page.Items[2].LikeCount != 0 {
		t.Fatal("like update mutated old snapshot")
	}
	page, _ = updated.Page(100, 0)
	if page.Items[2].LikeCount != 9999 {
		t.Fatal("like number did not update")
	}
	for _, args := range [][2]int{{-1, 50}, {104, 50}, {0, 51}, {0, -1}} {
		if _, err := updated.Page(args[0], args[1]); !errors.Is(err, ErrPage) {
			t.Fatal("invalid page accepted", args)
		}
	}
}

func TestKnownDeletedContentIsRemovedWithoutPromotingNewPins(t *testing.T) {
	items := make([]OrderItem, 7)
	for i := range items {
		items[i] = OrderItem{CommentID: resourceID(i + 1), PublishedAt: testAt.Add(time.Duration(i) * time.Second)}
	}
	snapshot, _ := NewSnapshot(Replies, items)
	removed := snapshot.Without(resourceID(2), resourceID(6))
	page, _ := removed.Page(0, 0)
	if !reflect.DeepEqual(itemIDs(page.Items), []string{resourceID(1), resourceID(3), resourceID(4), resourceID(5), resourceID(7)}) || len(removed.Preview()) != 4 || snapshot.Len() != 7 {
		t.Fatal("known deleted content remained or replacement was promoted")
	}
}

func TestSnapshotRejectsInvalidOrDuplicateResources(t *testing.T) {
	valid := OrderItem{resourceID(1), 0, testAt}
	for _, items := range [][]OrderItem{{valid, valid}, {{"", 0, testAt}}, {{resourceID(1), -1, testAt}}, {{resourceID(1), 0, time.Time{}}}} {
		if _, err := NewSnapshot(MainComments, items); !errors.Is(err, ErrInvalid) {
			t.Fatal("invalid snapshot accepted")
		}
	}
	empty, err := NewSnapshot(Replies, nil)
	page, pageErr := empty.Page(0, 0)
	if err != nil || pageErr != nil || page.Items == nil || page.NextOffset != nil || len(empty.Preview()) != 0 {
		t.Fatal("empty discussion is not a valid empty page")
	}
}

func TestSelectedSortCoversAllPagesAndKeepsSnapshot(t *testing.T) {
	items := make([]OrderItem, 103)
	for i := range items {
		items[i] = OrderItem{resourceID(i + 1), int64((i * 17) % 103), testAt.Add(time.Duration(i) * time.Second)}
	}
	for _, mode := range []SortMode{Recent, MostLiked, Relevant} {
		snapshot, err := NewSortedSnapshot(MainComments, items, mode)
		if err != nil {
			t.Fatal(err)
		}
		all := []OrderItem{}
		for offset := 0; offset < snapshot.Len(); offset += 50 {
			page, err := snapshot.Page(offset, 50)
			if err != nil {
				t.Fatal(err)
			}
			all = append(all, page.Items...)
		}
		if len(all) != 103 {
			t.Fatal("lost pagination rows")
		}
		if mode == Recent && all[0].CommentID != resourceID(103) {
			t.Fatal("recent did not select newest across pages")
		}
		for i := 1; i < len(all); i++ {
			if mode == Recent && all[i].PublishedAt.After(all[i-1].PublishedAt) {
				t.Fatal("recent order")
			}
			if mode == MostLiked && all[i].LikeCount > all[i-1].LikeCount {
				t.Fatal("likes order")
			}
		}
		updated, err := snapshot.WithLikeCount(all[102].CommentID, 9999)
		if err != nil {
			t.Fatal(err)
		}
		page, _ := updated.Page(100, 3)
		if page.Items[2].CommentID != all[102].CommentID {
			t.Fatal("like changed captured order")
		}
	}
	if _, err := NewSortedSnapshot(MainComments, items, "unknown"); err == nil {
		t.Fatal("invalid sort accepted")
	}
}
