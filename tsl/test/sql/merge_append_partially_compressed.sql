-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

-- this test checks the validity of the produced plans for partially compressed chunks
-- when injecting query_pathkeys on top of the append
-- path that combines the uncompressed and compressed parts of a chunk.

-- We're testing the MergeAppend here which is not compatible with parallel plans.
set max_parallel_workers_per_gather = 0;
set timescaledb.enable_decompression_sorted_merge = off;
\set PREFIX 'EXPLAIN (analyze, costs off, timing off, summary off)'

CREATE TABLE ht_metrics_compressed(time timestamptz, device int, value float);
SELECT create_hypertable('ht_metrics_compressed','time');
ALTER TABLE ht_metrics_compressed SET (timescaledb.compress, timescaledb.compress_segmentby='device', timescaledb.compress_orderby='time');

INSERT INTO ht_metrics_compressed
SELECT time, device, device * 0.1
FROM generate_series('2020-01-02'::timestamptz,'2020-01-18'::timestamptz,'6 hour') time,
generate_series(1,3) device;

SELECT compress_chunk(c) FROM show_chunks('ht_metrics_compressed') c;
-- make them partially compressed
INSERT INTO ht_metrics_compressed
SELECT time, device, device * 0.1
FROM generate_series('2020-01-02'::timestamptz,'2020-01-18'::timestamptz,'9 hour') time,
generate_series(1,3) device;

VACUUM ANALYZE ht_metrics_compressed;

-- chunkAppend eligible queries (from tsbench)
-- sort is not pushed down
:PREFIX SELECT * FROM ht_metrics_compressed ORDER BY time DESC, device LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed ORDER BY time_bucket('1d', time) DESC, device LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed ORDER BY time desc limit 10;
:PREFIX SELECT * FROM ht_metrics_compressed ORDER BY time_bucket('2d',time) DESC LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device IN (1,2,3) ORDER BY time DESC LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device IN (1,2,3) ORDER BY time, device DESC LIMIT 1;
-- index scan, no sort on top
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY time DESC LIMIT 1; -- index scan, no resorting required
SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY time DESC LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY device, time DESC LIMIT 1; -- this uses the index and does not do sort on top
SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY device, time DESC LIMIT 1;
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY time, device DESC LIMIT 1; -- this also uses the index and does not do sort on top
SELECT * FROM ht_metrics_compressed WHERE device = 3 ORDER BY time, device DESC LIMIT 1;

-- not eligible for chunkAppend, but eligible for sort pushdown
:PREFIX SELECT * FROM ht_metrics_compressed ORDER BY device, time DESC LIMIT 1; -- with pushdown
:PREFIX SELECT * FROM ht_metrics_compressed WHERE device IN (1,2,3) ORDER BY device, time DESC LIMIT 1; -- with pushdown

-- -- Test direct ordered select from a single partially compressed chunk
-- -- Note that this currently doesn't work: https://github.com/timescale/timescaledb/issues/7084
-- select * from show_chunks('ht_metrics_compressed') chunk order by chunk limit 1 \gset
--
-- :PREFIX
-- SELECT * FROM :chunk ORDER BY device, time LIMIT 5;
--
-- SELECT * FROM :chunk ORDER BY device, time LIMIT 5;
--
-- :PREFIX
-- SELECT * FROM :chunk ORDER BY device DESC, time DESC LIMIT 5;
--
-- SELECT * FROM :chunk ORDER BY device DESC, time DESC LIMIT 5;


CREATE TABLE test1 (
time timestamptz NOT NULL,
    x1 integer,
    x2 integer,
    x3 integer,
    x4 integer,
    x5 integer);

SELECT FROM create_hypertable('test1', 'time');

ALTER TABLE test1 SET (timescaledb.compress, timescaledb.compress_segmentby='x1, x2, x5', timescaledb.compress_orderby = 'time DESC, x3 ASC, x4 ASC');

INSERT INTO test1 (time, x1, x2, x3, x4, x5) values('2000-01-01 00:00:00-00', 1, 2, 1, 1, 0);
INSERT INTO test1 (time, x1, x2, x3, x4, x5) values('2000-01-01 01:00:00-00', 1, 3, 2, 2, 0);
INSERT INTO test1 (time, x1, x2, x3, x4, x5) values('2000-01-01 02:00:00-00', 2, 1, 3, 3, 0);
INSERT INTO test1 (time, x1, x2, x3, x4, x5) values('2000-01-01 03:00:00-00', 1, 2, 4, 4, 0);

SELECT compress_chunk(i) FROM show_chunks('test1') i;

-- make all the chunks partially compressed
INSERT INTO test1 (time, x1, x2, x3, x4, x5) values('2000-01-01 02:01:00-00', 10, 20, 30, 40 ,50);

ANALYZE test1;

-- tests that require resorting (pushdown below decompressChunk node cannot happen)

-- requires resorting, no pushdown can happen
:PREFIX
SELECT * FROM test1 ORDER BY time DESC LIMIT 10;

-- requires resorting
:PREFIX
SELECT * FROM test1 ORDER BY time DESC NULLS FIRST, x3 ASC NULLS LAST LIMIT 10;

-- all these require resorting, no pushdown can happen
:PREFIX
SELECT * FROM test1 ORDER BY time DESC NULLS FIRST, x3 ASC NULLS LAST, x4 ASC NULLS LAST LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY time DESC NULLS FIRST, x3 ASC NULLS LAST, x4 DESC NULLS FIRST LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY time ASC NULLS LAST LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY time ASC NULLS LAST, x3 DESC NULLS FIRST LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY time ASC NULLS LAST, x3 DESC NULLS FIRST, x4 DESC NULLS FIRST LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY time ASC NULLS FIRST, x3 DESC NULLS LAST, x4 ASC LIMIT 10;

set enable_hashagg to off; -- different on PG13

:PREFIX
SELECT x1, x2, max(time) FROM (SELECT * FROM test1 ORDER BY time, x1, x2 LIMIT 10) t
GROUP BY x1, x2, time ORDER BY time limit 10;

reset enable_hashagg;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, x4, time LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time, x4 LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time, x3 LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time, x3, x4 LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time, x4 DESC LIMIT 10; -- no pushdown because orderby does not match

-- queries with pushdown
:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time LIMIT 10;

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time DESC, x3 ASC, x4 ASC LIMIT 10; -- pushdown

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time ASC, x3 DESC, x4 DESC LIMIT 10; -- pushdown

:PREFIX
SELECT * FROM test1 ORDER BY x1, x2, x5, time, x3 DESC LIMIT 10;

-- test append with join column in orderby
-- #6975

CREATE TABLE join_table (
	x1 integer,
	y1 float);

INSERT INTO join_table VALUES (1, 1.0), (2,2.0);

:PREFIX
SELECT * FROM test1 t1 JOIN join_table jt ON t1.x1 = jt.x1
ORDER BY t1.x1, jt.y1;

---------------------------------------------------------------------------
-- test queries without ordered append, but still eligible for sort pushdown
---------------------------------------------------------------------------

CREATE TABLE test2 (
time timestamptz NOT NULL,
    x1 integer,
    x2 integer,
    x3 integer,
    x4 integer,
    x5 integer);

SELECT FROM create_hypertable('test2', 'time');

ALTER TABLE test2 SET (timescaledb.compress, timescaledb.compress_segmentby='x1, x2, x5', timescaledb.compress_orderby = 'x3 ASC, x4 ASC');

INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-01 00:00:00-00', 1, 2, 1, 1, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-01 01:00:00-00', 1, 3, 2, 2, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-01 02:00:00-00', 2, 1, 3, 3, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-01 03:00:00-00', 1, 2, 4, 4, 0);
-- chunk 2
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-10 00:00:00-00', 1, 2, 5, 5, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-10 01:00:00-00', 1, 3, 6, 6, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-10 02:00:00-00', 2, 1, 7, 7, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-10 03:00:00-00', 1, 2, 8, 8, 0);

SELECT compress_chunk(i) FROM show_chunks('test2') i;
-- make them partially compressed
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-01 00:02:01-00', 1, 2,  9,  9, 0);
INSERT INTO test2 (time, x1, x2, x3, x4, x5) values('2000-01-10 00:02:01-00', 1, 2, 10, 10, 0);

ANALYZE test2;

set enable_indexscan = off;
-- queries where sort is pushed down
:PREFIX SELECT * FROM test2 ORDER BY x1, x2, x5, x3 LIMIT 10;
SELECT * FROM test2 ORDER BY x1, x2, x5, x3 LIMIT 10;
:PREFIX SELECT * FROM test2 ORDER BY x1, x2, x5, x3, x4 LIMIT 10;
SELECT * FROM test2 ORDER BY x1, x2, x5, x3, x4 LIMIT 10;

-- queries where sort is not pushed down
:PREFIX SELECT * FROM test2 ORDER BY x1, x2, x3 LIMIT 10;
SELECT * FROM test2 ORDER BY x1, x2, x3 LIMIT 10;
:PREFIX SELECT * FROM test2 ORDER BY x1, x2, x5, x4 LIMIT 10;
SELECT * FROM test2 ORDER BY x1, x2, x5, x4 LIMIT 10;
:PREFIX SELECT * FROM test2 ORDER BY x1, x2, x5, time LIMIT 10;
SELECT * FROM test2 ORDER BY x1, x2, x5, time LIMIT 10;

-----------------------------
-- tests with space partitioning
-----------------------------
CREATE TABLE test3 (
time timestamptz NOT NULL,
    x1 integer,
    x2 integer,
    x3 integer,
    x4 integer,
    x5 integer);

SELECT FROM create_hypertable('test3', 'time');
SELECT add_dimension('test3', 'x1', number_partitions => 2);

ALTER TABLE test3 SET (timescaledb.compress, timescaledb.compress_segmentby='x1, x2, x5', timescaledb.compress_orderby = 'x3 ASC, x4 ASC');

INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-01 00:00:00-00', 1, 2, 1, 1, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-01 01:00:00-00', 1, 3, 2, 2, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-01 02:00:00-00', 2, 1, 3, 3, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-01 03:00:00-00', 1, 2, 4, 4, 0);
-- chunk 2
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-10 00:00:00-00', 1, 2, 5, 5, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-10 01:00:00-00', 1, 3, 6, 6, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-10 02:00:00-00', 2, 1, 7, 7, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-10 03:00:00-00', 1, 2, 8, 8, 0);

SELECT compress_chunk(i) FROM show_chunks('test3') i;
-- make them partially compressed
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-01 00:02:01-00', 1, 2,  9,  9, 0);
INSERT INTO test3 (time, x1, x2, x3, x4, x5) values('2000-01-10 00:02:01-00', 1, 2, 10, 10, 0);

ANALYZE test3;

set enable_indexscan = off;
-- queries where sort is pushed down
:PREFIX SELECT * FROM test3 ORDER BY x1, x2, x5, x3 LIMIT 10;
SELECT * FROM test3 ORDER BY x1, x2, x5, x3 LIMIT 10;
:PREFIX SELECT * FROM test3 ORDER BY x1, x2, x5, x3, x4 LIMIT 10;
SELECT * FROM test3 ORDER BY x1, x2, x5, x3, x4 LIMIT 10;

-- queries where sort is not pushed down
:PREFIX SELECT * FROM test3 ORDER BY x1, x2, x3 LIMIT 10;
SELECT * FROM test3 ORDER BY x1, x2, x3 LIMIT 10;
:PREFIX SELECT * FROM test3 ORDER BY x1, x2, x5, x4 LIMIT 10;
SELECT * FROM test3 ORDER BY x1, x2, x5, x4 LIMIT 10;
:PREFIX SELECT * FROM test3 ORDER BY x1, x2, x5, time LIMIT 10;
SELECT * FROM test3 ORDER BY x1, x2, x5, time LIMIT 10;

reset enable_indexscan;

-- test ordering on single chunk queries
CREATE TABLE test4(time timestamptz not null, device text, value float);
SELECT table_name FROM create_hypertable('test4','time',chunk_time_interval:='1 year'::interval);

ALTER TABLE test4 SET (tsdb.compress, tsdb.compress_segmentby='device', tsdb.compress_orderby='time');

INSERT INTO test4 SELECT '2025-01-01', NULL, 0.1;
INSERT INTO test4 SELECT '2025-01-02', NULL, 0.1;
INSERT INTO test4 SELECT '2025-01-02', 'd', 0.1;
SELECT count(compress_chunk(ch)) FROM show_chunks('test4') ch;
INSERT INTO test4 SELECT '2025-01-02', 'd', 0.1;
VACUUM ANALYZE test4;

set enable_hashagg TO false;
SELECT time, device FROM _timescaledb_internal._hyper_9_21_chunk GROUP BY time, device;
EXPLAIN (costs off, analyze, timing off, summary off) SELECT time, device FROM _timescaledb_internal._hyper_9_21_chunk GROUP BY time, device;

reset timescaledb.enable_decompression_sorted_merge;
reset max_parallel_workers_per_gather;
