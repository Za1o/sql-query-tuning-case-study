# SQL Query Tuning: From 839 ms to 22.6 ms with Two Indexes

A query-performance case study from INF407 (Modern Issues in Databases) at the University at Albany. I benchmarked the same seven-table join query in MySQL 8.0.46 (MySQL Workbench, `EXPLAIN ANALYZE`), changed one thing at a time, and re-measured.

> The same seven-table query returned 74 rows at every stage. With both indexes in place, its recorded runtime fell from 839 ms to 22.6 ms (97.3%). Adding the join-order hint brought it back up to 46.1 ms.

## The query

The query joins `student`, `enrollment`, `section`, `department`, `faculty`, `address`, and `course`, applies eight filters (including a faculty-job subquery), and sorts by last name, grade, faculty name, and major. It returned **74 rows** at every stage, so the stages are directly comparable — same query, same output, only the execution changed. The full query is in [`query_tuning_excerpt.sql`](query_tuning_excerpt.sql).

## What the baseline plan showed

Baseline runtime: **839 ms** (top `Sort` operation, `EXPLAIN ANALYZE`).

The estimated plan pointed straight at the problem:

| Table | Access type | Key used | Est. rows examined | Notes |
| --- | --- | --- | ---: | --- |
| enrollment | `ALL` (full scan) | none | 701,792 | Using where; using join buffer (hash join) |
| eligible (subquery, materialized) | `ALL` (full scan) | none | 39,951 | Builds the eligible-job list |
| department | `ALL` (full scan) | none | 16 | Using temporary; using filesort |
| section | `range` | PRIMARY | 2,627 | Using where; using join buffer |

Enrollment was the first target: a full scan of an estimated 701,792 rows on the largest join in the query, with no usable key. Its primary key starts with `Student_ID`, so it could not serve lookups by section or grade.

## What I changed, and what happened

### Change 1 — Index enrollment by section and grade

```sql
CREATE INDEX idx_m42_enrollment_section_grade
  ON enrollment (Section_ID, Grade);
```

The new index gives MySQL a way to find enrollment records by section and check the grade filter (`Grade > '1.33'`) from the index.

**839 ms → 46.2 ms — a 94.5% improvement (18.2× faster).** This was the largest single drop in the test.

### Change 2 — Add an index on section (the best result)

```sql
CREATE INDEX idx_m42_section_course_semester
  ON section (Dept_ID, Course_Number, Semester);
```

Kept the enrollment index and added this one. The first two columns match the join to `course` (`Course_Number` + `Dept_ID`), and the third lets MySQL check the semester filter (`Semester <> 'Summer'`) from the indexed value.

**46.2 ms → 22.6 ms — 97.3% below the 839 ms baseline (37.1× faster).**

### Change 3 — Force the join order (a negative result)

Kept both indexes and added a `JOIN_PREFIX(c, sec, e)` hint to start with Course, Section, and Enrollment.

**22.6 ms → 46.1 ms — 23.5 ms slower (a 104.0% increase over Change 2).** Forcing my preferred order was worse than the order MySQL's optimizer chose on its own. I kept this in the case study because it is the most useful lesson in it: measure the hint, don't assume it helps.

## Results summary

| Stage | Change | Runtime | vs. baseline |
| --- | --- | ---: | ---: |
| Baseline | No secondary indexes (primary keys only) | 839 ms | — |
| Change 1 | Index on `enrollment (Section_ID, Grade)` | 46.2 ms | −94.5% |
| Change 2 | + Index on `section (Dept_ID, Course_Number, Semester)` | **22.6 ms** | **−97.3%** |
| Change 3 | + `JOIN_PREFIX` hint | 46.1 ms | −94.5% |

Runtimes are the `EXPLAIN ANALYZE` top-operation time in milliseconds — one recorded runtime per stage, as documented in the original report — and exclude index creation and result fetching. Every stage returned the same 74 rows.

**Unavailable:** the full Change 2 execution plan. The original report contains only the top-line actual plan (runtime and row count) for each stage, so this case study does not claim a specific after-plan access type or key for Change 2; the baseline estimated plan above is the full plan available.

## What I would do next

- Use the two indexes without the join-order hint for this query, and retest after the next data refresh.
- Repeat each stage under similar cache conditions — with one run per stage, I can't yet say how stable the Change 2 vs. Change 3 gap is.
- Look at the faculty subquery next: the baseline plan materialized it with a full scan (est. 39,951 rows).
- Remember the trade-off: indexes cost storage and add work on inserts and updates to indexed columns.

## Tools used

MySQL 8.0.46, MySQL Workbench, `EXPLAIN` / `EXPLAIN ANALYZE`, SQL (joins, subqueries, composite indexes, optimizer hints).

*Course project, INF407 Assignment 4B. The excerpt in this repo is limited to the benchmarked query and the two index statements; the course dataset is not included.*
