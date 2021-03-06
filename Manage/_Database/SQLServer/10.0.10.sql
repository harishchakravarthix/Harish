truncate table dbversion;
go
insert into dbversion(dbversion) values ('10.0.10');
go

ALTER PROCEDURE [dbo].[spUsers_UserCount]
	@BusinessUnitGuid uniqueidentifier
AS
BEGIN
	SELECT SUM(CASE WHEN IsGuest = 0 AND Disabled = 0 AND IsAnonymousUser = 0 THEN 1 ELSE 0 END) 
	FROM Intelledox_User
	WHERE Business_Unit_GUID = @BusinessUnitGuid;
END
GO

ALTER PROCEDURE [dbo].[spProject_ProjectListFullTextByFolder]
	@UserGuid uniqueidentifier,
	@ProjectTypeId int,
	@SearchString nvarchar(100),
	@FullText nvarChar(1000),
	@FolderGuid uniqueidentifier
AS
	declare @HasRole bit
	declare @BusinessUnitGUID uniqueidentifier

	SELECT	@BusinessUnitGUID = Business_Unit_GUID
	FROM	Intelledox_User
	WHERE	User_Guid = @UserGuid;

	IF EXISTS(SELECT	vwUserPermissions.*
		FROM	vwUserPermissions
		WHERE	vwUserPermissions.CanDesignProjects = 1
				AND vwUserPermissions.UserGuid = @UserGuid)
	BEGIN
		SET @HasRole = 1;
	END

	BEGIN
		SELECT 	T.template_id, T.[name] as project_name, T.template_type_id,
				T.template_guid, T.template_version, T.import_date, 
				T.Business_Unit_GUID, T.Supplier_Guid, T.Modified_Date, Intelledox_User.Username,
				T.Modified_By, lockedByUser.Username AS LockedBy,
				T.FeatureFlags, T.FolderGuid
		FROM	Template T
				LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = T.Modified_By
				LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = T.LockedByUserGuid
		WHERE	@HasRole = 1
			AND T.Business_Unit_GUID = @BusinessUnitGUID
			AND (T.FolderGuid = @FolderGuid OR (@FolderGuid IS NULL AND T.FolderGuid IS NULL))
			AND T.Name COLLATE Latin1_General_CI_AI LIKE (@SearchString + '%') COLLATE Latin1_General_CI_AI
			AND T.Template_Type_Id = @ProjectTypeId OR @ProjectTypeId = 0
			AND (T.Template_Guid IN (
					SELECT	Template_Guid
					FROM	Template_File tf
					WHERE	Contains(*, @FullText)
				))
		ORDER BY T.Name
	END
GO
