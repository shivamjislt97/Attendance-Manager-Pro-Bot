PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE students (
                chat_id    TEXT PRIMARY KEY,
                naam       TEXT,
                branch     TEXT,
                roll_no    TEXT,
                unique_id  TEXT UNIQUE,
                registered_at TEXT DEFAULT (datetime('now'))
            , year TEXT, role TEXT DEFAULT 'student' CHECK(role IN ('student','admin')));
INSERT INTO students VALUES('6267031612','Shivam ji','CS','2405210100046','STU-52DBFEDE','2026-08-06 09:00:00','3rd Year','admin');
INSERT INTO students VALUES('8625984731','Tester','CS','2405210199946','STU-A75B38BB','2026-09-02 20:58:24',NULL,'student');
INSERT INTO students VALUES('5320957474','Prince','IT','2405210130016','STU-CDD9579E','2026-08-20 00:00:00','3rd Year','student');
INSERT INTO students VALUES('6454713102','Shivam saini','CS','2505210100044','STU-C6F234F5','2026-09-05 03:29:30','2nd Year','student');
INSERT INTO students VALUES('8789584247','Dev Sharma','CS','000000000000','STU-DE496259','2026-09-09 03:22:29','1st Year','student');
CREATE TABLE attendance (
                date       TEXT,
                chat_id    TEXT,
                status     TEXT NOT NULL,
                marked_by  TEXT NOT NULL DEFAULT 'self',
                PRIMARY KEY (date, chat_id),
                FOREIGN KEY (chat_id) REFERENCES students(chat_id)
            );
INSERT INTO attendance VALUES('12/08/2026','6267031612','PRESENT','admin');
INSERT INTO attendance VALUES('18/08/2026','6267031612','PRESENT','admin');
INSERT INTO attendance VALUES('31/08/2026','6267031612','PRESENT','admin');
INSERT INTO attendance VALUES('01/09/2026','6267031612','PRESENT','admin');
INSERT INTO attendance VALUES('02/09/2026','6267031612','PRESENT','admin');
INSERT INTO attendance VALUES('03/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('06/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('07/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('08/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('11/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('13/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('14/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('15/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('19/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('20/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('21/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('25/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('27/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('29/08/2026','6267031612','ABSENT','admin');
INSERT INTO attendance VALUES('20/08/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('21/08/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('31/08/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('01/09/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('02/09/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('03/09/2026','5320957474','PRESENT','admin-manual');
INSERT INTO attendance VALUES('03/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('04/09/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('04/09/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('04/09/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('10/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('10/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('10/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('17/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('17/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('17/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('22/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('22/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('22/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('24/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('24/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('24/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('26/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('26/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('26/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('28/08/2026','6267031612','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('28/08/2026','8625984731','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('28/08/2026','5320957474','HOLIDAY','admin-holiday: holiday declared by admin');
INSERT INTO attendance VALUES('05/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('05/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('05/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('05/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('07/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('07/09/2026','6267031612','ABSENT','self');
INSERT INTO attendance VALUES('07/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('07/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('08/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('08/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('08/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('08/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('09/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('09/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('09/09/2026','8789584247','PRESENT','self');
INSERT INTO attendance VALUES('09/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('09/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('10/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('10/09/2026','8789584247','PRESENT','self');
INSERT INTO attendance VALUES('10/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('10/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('10/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('11/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('11/09/2026','8789584247','PRESENT','self');
INSERT INTO attendance VALUES('11/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('11/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('11/09/2026','6267031612','PRESENT','self');
INSERT INTO attendance VALUES('12/09/2026','6454713102','PRESENT','self');
INSERT INTO attendance VALUES('12/09/2026','8789584247','PRESENT','self');
INSERT INTO attendance VALUES('12/09/2026','6267031612','ABSENT','self');
INSERT INTO attendance VALUES('12/09/2026','8625984731','ABSENT','bot-auto');
INSERT INTO attendance VALUES('12/09/2026','5320957474','ABSENT','bot-auto');
INSERT INTO attendance VALUES('14/0