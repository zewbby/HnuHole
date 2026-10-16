package channels

import (
	"sort"

	"github.com/google/uuid"
)

type catalogEntry struct {
	id               uuid.UUID
	code             string
	name             string
	displayOrder     int
	initiallyVisible bool
}

var expectedCatalog = [...]catalogEntry{
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000001"), code: "vent", name: "吐槽", displayOrder: 10, initiallyVisible: true},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000002"), code: "warning", name: "避雷", displayOrder: 20, initiallyVisible: true},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000003"), code: "recommendation", name: "安利", displayOrder: 30, initiallyVisible: true},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000004"), code: "buddy", name: "搭子", displayOrder: 40, initiallyVisible: true},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000005"), code: "emotion", name: "情感", displayOrder: 50, initiallyVisible: true},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000006"), code: "mutual_help", name: "互助", displayOrder: 60, initiallyVisible: false},
	{id: uuid.MustParse("5f6f4f88-8f64-4bb2-9d34-000000000007"), code: "technology", name: "科技", displayOrder: 70, initiallyVisible: false},
}

func ValidateCatalog(items []Channel) error {
	if len(items) != len(expectedCatalog) {
		return ErrInvalidCatalog
	}

	byCode := make(map[string]Channel, len(items))
	byID := make(map[uuid.UUID]struct{}, len(items))
	for _, item := range items {
		if item.ID == uuid.Nil || item.Code == "" || item.Name == "" {
			return ErrInvalidCatalog
		}
		if _, exists := byCode[item.Code]; exists {
			return ErrInvalidCatalog
		}
		if _, exists := byID[item.ID]; exists {
			return ErrInvalidCatalog
		}
		byCode[item.Code] = item
		byID[item.ID] = struct{}{}
	}

	for _, expected := range expectedCatalog {
		item, ok := byCode[expected.code]
		if !ok || item.ID != expected.id || item.Name != expected.name || item.DisplayOrder != expected.displayOrder || item.InitiallyVisible != expected.initiallyVisible {
			return ErrInvalidCatalog
		}
	}
	return nil
}

func Sort(items []Channel) {
	sort.SliceStable(items, func(i, j int) bool {
		return items[i].DisplayOrder < items[j].DisplayOrder
	})
}
