truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.7.1');
go
ALTER VIEW dbo.vwUserAI
AS
	SELECT u.Business_Unit_GUID as BusinessUnitGuid,
			u.User_Guid as UserGuid,
			u.IsGuest,
			u.Username COLLATE Latin1_General_CI_AI as Username,
			ud.First_Name COLLATE Latin1_General_CI_AI as FirstName,
			ud.Last_Name COLLATE Latin1_General_CI_AI as LastName
	FROM Intelledox_User u
		LEFT JOIN Address_Book ud ON u.Address_ID = ud.Address_ID;
GO
