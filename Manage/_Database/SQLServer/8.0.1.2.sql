/*
** Database Update package 8.0.1.2
*/

--set version
truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.0.1.2');
go
