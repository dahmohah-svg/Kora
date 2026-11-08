-- Local development data (supabase db reset). Not used in production.
-- Pitch names are placeholders; add real partner pitches through the admin panel.
insert into public.pitches (name, area, address, lat, lng, price_per_hour_egp) values
  ('Pitch A (sample)', 'Maadi',     'Road 9, Maadi',          29.9602, 31.2569, 600),
  ('Pitch B (sample)', 'Maadi',     'Degla, Maadi',           29.9590, 31.2790, 500),
  ('Pitch C (sample)', 'Nasr City', 'Abbas El Akkad, Nasr City', 30.0566, 31.3400, 550);
