-- SQL Query Tuning case study (INF407, MySQL 8.0.46)
-- The same query was benchmarked with EXPLAIN ANALYZE at each stage.
-- Runtimes (top Sort operation, ms): Baseline 839 | Change 1 46.2 | Change 2 22.6 | Change 3 46.1
-- Every stage returned 74 rows.

-- The benchmarked query (baseline form, no secondary indexes)
EXPLAIN ANALYZE
SELECT *
FROM student AS s
JOIN enrollment AS e ON s.ID = e.Student_ID
JOIN section AS sec ON sec.ID = e.Section_ID
JOIN department AS d ON s.Major = d.Name
JOIN faculty AS f ON f.ID = sec.Faculty_ID
JOIN address AS a ON a.ID = s.Address_ID
JOIN course AS c ON sec.Course_Number = c.Num AND sec.Dept_ID = c.Dept_ID
WHERE s.Name_Last NOT LIKE ''
  AND s.Major <> 'Theater'
  AND e.Grade > '1.33'
  AND f.Job IN (
      SELECT eligible.Job
      FROM faculty AS eligible
      WHERE eligible.Job NOT IN ('Administrative', 'General Services', 'Human Resources')
        AND eligible.Dept <> 'THT'
  )
  AND e.Section_ID >= 1
  AND sec.Semester <> 'Summer'
  AND s.Advisor_ID <> sec.Faculty_ID
  AND s.Address_ID <> f.Address_ID
ORDER BY s.Name_Last, e.Grade DESC, f.Name_Last, s.Major;

-- Change 1: index enrollment by section and grade  (839 ms -> 46.2 ms)
CREATE INDEX idx_m42_enrollment_section_grade ON enrollment (Section_ID, Grade);

-- Change 2: also index section by department, course number, semester  (46.2 ms -> 22.6 ms)
CREATE INDEX idx_m42_section_course_semester ON section (Dept_ID, Course_Number, Semester);

-- Change 3: keeping both indexes, the query was rerun with this hint added
-- to the SELECT above. It was slower (22.6 ms -> 46.1 ms), so the final
-- recommendation is the two indexes without the hint.
--   SELECT /*+ JOIN_PREFIX(c, sec, e) */ *
