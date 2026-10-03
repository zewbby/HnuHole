package channels

import (
	"context"

	"github.com/jackc/pgx/v5"
)

const listChannelsQuery = `
SELECT id, code, name, initially_visible, display_order
FROM public.channels
ORDER BY display_order ASC`

// Queryer exposes only query access; both pgx.Tx and pgxpool.Pool satisfy it.
// Business callbacks cannot commit or roll back the authorization transaction.
type Queryer interface {
    Query(context.Context, string, ...any) (pgx.Rows, error)
}

type PostgresRepository struct {
    query Queryer
}

func NewPostgresRepository(query Queryer) *PostgresRepository {
	return &PostgresRepository{query: query}
}

func (r *PostgresRepository) List(ctx context.Context) ([]Channel, error) {
	rows, err := r.query.Query(ctx, listChannelsQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]Channel, 0, len(expectedCatalog))
	for rows.Next() {
		var item Channel
		if err := rows.Scan(&item.ID, &item.Code, &item.Name, &item.InitiallyVisible, &item.DisplayOrder); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}
