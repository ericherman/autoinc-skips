drop table if exists bp_pid;
create table if not exists bp_pid(
`row_id` int(11)NOT NULL AUTO_INCREMENT,
patient_id INT,
category varchar(2),
birthdate datetime,
PRIMARY KEY (row_id)
) ENGINE=InnoDB;

BEGIN;
insert into bp_pid
select null, patient_id, 'ht', birthdate
from hypertension_pid join person on hypertension_pid.patient_id = person.person_id
where birthdate >= '1959-12-01' limit 17;

insert into bp_pid
select null, patient_id, 'ht', birthdate
from hypertension_pid join person on hypertension_pid.patient_id = person.person_id
where birthdate >= '1949-12-01' and birthdate < '1959-12-01' limit 25;

insert into bp_pid
select null, patient_id, 'ht', birthdate
from hypertension_pid join person on hypertension_pid.patient_id = person.person_id
where birthdate >= '1944-12-01' and birthdate < '1949-12-01' limit 16;

insert into bp_pid
select null, patient_id, 'ht', birthdate
from hypertension_pid join person on hypertension_pid.patient_id = person.person_id
where birthdate < '1944-12-01' limit 1;

COMMIT;

SELECT * FROM bp_pid;

SELECT MAX(row_id), COUNT(*) FROM bp_pid;
