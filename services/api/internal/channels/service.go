package channels

import "context"

type Service struct {
	repository Repository
}

func NewService(repository Repository) *Service {
	return &Service{repository: repository}
}

func (s *Service) List(ctx context.Context) ([]Channel, error) {
	items, err := s.repository.List(ctx)
	if err != nil {
		return nil, err
	}
	Sort(items)
	if err := ValidateCatalog(items); err != nil {
		return nil, err
	}
	return items, nil
}
