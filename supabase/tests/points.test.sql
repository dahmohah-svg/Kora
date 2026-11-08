-- Rank points and levels, exactly as in the plan.
select t.eq(public.level_for_points(0),   'rookie',  'level at 0');
select t.eq(public.level_for_points(49),  'rookie',  'level at 49');
select t.eq(public.level_for_points(50),  'regular', 'level at 50');
select t.eq(public.level_for_points(150), 'starter', 'level at 150');
select t.eq(public.level_for_points(300), 'captain', 'level at 300');
select t.eq(public.level_for_points(599), 'captain', 'level at 599');
select t.eq(public.level_for_points(600), 'legend',  'level at 600');

select t.eq(public.rating_points(1),    -6, '1 star = -6');
select t.eq(public.rating_points(3),     0, '3 stars = 0');
select t.eq(public.rating_points(5),     6, '5 stars = +6');
select t.eq(public.rating_points(4.5),   5, '4.5 stars rounds 4.5 up to +5');
select t.eq(public.rating_points(null),  0, 'no ratings = 0');

select t.eq(public.match_points('on_time', 5),    21, 'on time + 5 stars = 10 + 5 + 6');
select t.eq(public.match_points('on_time', null), 15, 'on time, not rated = 15');
select t.eq(public.match_points('late', 3),        7, 'late still gets +10, minus 3');
select t.eq(public.match_points('late', 1),        1, 'late with 1 star = 10 - 3 - 6');
select t.eq(public.match_points('no_show', 5),   -20, 'no-show = -20, ratings ignored');
