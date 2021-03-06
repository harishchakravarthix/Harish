truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.7.1.12');
go
DROP VIEW vwUserAI
GO
DROP VIEW vwProjectAI
GO
DROP VIEW vwUserGroupSubscriptionAI
GO
CREATE VIEW dbo.vwUserAI
AS
	SELECT u.Business_Unit_GUID as BusinessUnitGuid,
			u.User_Guid as UserGuid,
			u.IsGuest,
			u.Username COLLATE Latin1_General_CI_AI as Username,
			ud.First_Name COLLATE Latin1_General_CI_AI as FirstName,
			ud.Last_Name COLLATE Latin1_General_CI_AI as LastName
	FROM Intelledox_User u
		LEFT JOIN Address_Book ud ON u.Address_ID = ud.Address_ID
	WHERE u.Disabled = 0;
GO
CREATE VIEW dbo.vwProjectAI
AS
	SELECT	p.Business_Unit_GUID as BusinessUnitGuid,
			p.Template_Guid as ProjectGuid,
			p.Name COLLATE Latin1_General_CI_AI as Name
	FROM	Template p
GO
CREATE VIEW dbo.vwUserGroupSubscriptionAI
AS
	SELECT	ugs.*
	FROM	User_Group_Subscription ugs
GO
DROP PROCEDURE spProject_GetProjectVersionByPublishedBy
GO
DROP PROCEDURE dbo.spProject_GetVersionModifiedDate
GO
CREATE PROCEDURE dbo.spProject_GetProjectVersionByPublishedBy
	@ProjectGuid uniqueidentifier, 
	@PublishedBy datetime
AS
BEGIN

    SELECT MAX(Versions.Template_Version)
    FROM (SELECT Template.Template_Version
			FROM Template
			WHERE Template.Template_Guid = @ProjectGuid
				AND Template.Modified_Date <= @PublishedBy
		UNION
			SELECT Template_Version.Template_Version
			FROM Template_Version
			WHERE Template_Version.Template_Guid = @ProjectGuid
				AND Template_Version.Modified_Date <= @PublishedBy) Versions
END
GO
CREATE PROCEDURE dbo.spProject_GetVersionModifiedDate
	@ProjectGuid uniqueidentifier,
	@Version varchar(10)
AS
BEGIN
		SELECT Template.Modified_Date
		FROM Template
		WHERE Template.Template_Version = @Version
			AND Template.Template_Guid = @ProjectGuid
	UNION
		SELECT Template_Version.Modified_Date
		FROM Template_Version
		WHERE Template_Version.Template_Version = @Version
			AND Template_Version.Template_Guid = @ProjectGuid
END
GO
