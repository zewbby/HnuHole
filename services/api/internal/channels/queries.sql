-- name: ListChannels :many
SELECT id, code, name, initially_visible, display_order
FROM public.channels
ORDER BY display_order ASC;
