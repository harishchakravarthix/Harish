truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.0.0.5');
go

CREATE PROCEDURE [dbo].[spTemplate_GetDSProviderDependency] (
	@TemplateGroupGuid uniqueidentifier,
	@PublishedBy datetime
)
AS

	DECLARE @TemplateGuid uniqueidentifier
	DECLARE @TemplateVersion nvarchar(10)


	SELECT @TemplateGuid = TemplateGuid,
		   @TemplateVersion = TemplateVersion
	FROM
(
	SELECT	Template.Template_Guid AS TemplateGuid, 
			Template.Template_Version AS TemplateVersion
	FROM	Template_Group
			INNER JOIN Template ON (Template_Group.Template_Guid = Template.Template_Guid 
					AND (Template_Group.Template_Version IS NULL
						OR Template_Group.Template_Version = Template.Template_Version))
				OR (Template_Group.Layout_Guid = Template.Template_Guid
					AND (Template_Group.Layout_Version IS NULL
						OR Template_Group.Layout_Version = Template.Template_Version))
	WHERE	Template_Group.Template_Group_Guid = @TemplateGroupGuid
		AND (Template_Group.MatchProjectVersion = 0 
			OR Template.Modified_Date <= @PublishedBy)
			
	UNION ALL
	
	SELECT	Template_Version.Template_Guid AS TemplateGuid, 
			Template_Version.Template_Version AS TemplateVersion
	FROM	Template_Group
			INNER JOIN Template ON Template_Group.Template_Guid = Template.Template_Guid
			INNER JOIN Template_Version ON (Template_Group.Template_Guid = Template_Version.Template_Guid 
					AND Template_Group.Template_Version = Template_Version.Template_Version
					AND Template_Group.MatchProjectVersion = 0)
				OR (Template_Group.Layout_Guid = Template_Version.Template_Guid
					AND Template_Group.Layout_Version = Template_Version.Template_Version
					AND Template_Group.MatchProjectVersion = 0)
				OR (Template_Group.MatchProjectVersion = 1 
					AND ((Template_Group.Template_Guid = Template_Version.Template_Guid
							OR Template_Group.Layout_Guid = Template_Version.Template_Guid)
						AND Template.Modified_Date > @PublishedBy
						AND Template_Version.Modified_Date = (SELECT TOP 1 VersionDate.Modified_Date
							FROM Template_Version VersionDate
							WHERE VersionDate.Template_Guid = Template.Template_Guid
								AND VersionDate.Modified_Date <= @PublishedBy
							ORDER BY VersionDate.Modified_Date DESC)))
	WHERE	Template_Group.Template_Group_Guid = @TemplateGroupGuid
)	TEMPLATEDATA;	

	SELECT	DISTINCT Provider_Name
	FROM	Data_Service
			JOIN Data_Object ON Data_Service.Data_Service_Guid = Data_Object.Data_Service_Guid
			JOIN Xtf_Datasource_Dependency ON Xtf_Datasource_Dependency.Data_Object_Guid = Data_Object.Data_Object_Guid
	WHERE	Template_Guid = @TemplateGuid AND Template_Version = @TemplateVersion;


GO

ALTER procedure [dbo].[spProject_RestoreVersion]
	@ProjectGuid uniqueidentifier,
	@VersionNumber nvarchar(10),
	@UserGuid uniqueidentifier,
	@RestoreVersionComment nvarchar(50),
	@NextVersion nvarchar(10)
as
	SET NOCOUNT ON

	BEGIN TRAN	
		DECLARE @BusinessUnitGuid uniqueidentifier;

		SELECT TOP 1 @BusinessUnitGuid = Business_Unit_Guid 
		FROM Template
		WHERE Template_Guid = @ProjectGuid;
	
		INSERT INTO Template_Version 
			(Template_Version, 
			Template_Guid, 
			Modified_Date, 
			Modified_By,
			Project_Definition,
			Comment,
			IsMajorVersion,
			FeatureFlags,
			EncryptedProjectDefinition)
		SELECT Template.Template_Version,
			Template.Template_Guid,
			Template.Modified_Date,	
			Template.Modified_By,
			Template.Project_Definition,
			Template.Comment,
			Template.IsMajorVersion,
			Template.FeatureFlags,
			Template.EncryptedProjectDefinition
		FROM Template
		WHERE Template.Template_Guid = @ProjectGuid;
			
		INSERT INTO Template_File_Version (Template_Guid, File_Guid, Template_Version, [Binary],
				FormatTypeId)
		SELECT	Template.Template_Guid, Template_File.File_Guid, Template.Template_Version, 
				Template_File.[Binary], Template_File.FormatTypeId
		FROM	Template
				INNER JOIN Template_File ON Template.Template_Guid = Template_File.Template_Guid
		WHERE	Template.Template_Guid = @ProjectGuid;
		
		UPDATE	Template
		SET		Project_Definition = Template_Version.Project_Definition, 
				Template_Version = @NextVersion, 
				Comment = @RestoreVersionComment,
				Modified_Date = GetUTCdate(),
				Modified_By = @UserGuid,
				IsMajorVersion = 1,
				FeatureFlags = Template_Version.FeatureFlags,
				EncryptedProjectDefinition = Template_Version.EncryptedProjectDefinition
		FROM	Template
				INNER JOIN Template_Version ON Template.Template_Guid = Template_Version.Template_Guid
		WHERE	Template_Version.Template_Guid = @ProjectGuid
				AND Template_Version.Template_Version = @VersionNumber
		
		DELETE FROM Template_File
		WHERE	Template_Guid = @ProjectGuid;
		
		INSERT INTO Template_File(Template_Guid, File_Guid, [Binary], FormatTypeId)
		SELECT	@ProjectGuid, Template_File_Version.File_Guid, Template_File_Version.[Binary],
				Template_File_Version.FormatTypeId
		FROM	Template_File_Version 
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber; 
				
		EXEC spProject_DeleteOldProjectVersion @ProjectGuid=@ProjectGuid, 
			@NextVersion=@NextVersion,
			@BusinessUnitGuid=@BusinessUnitGuid;

		EXEC spProjectGroup_UpdateFeatureFlags @ProjectGuid=@ProjectGuid;
		
		--copy over dependencies from the source version
		INSERT INTO Xtf_ContentLibrary_Dependency(Template_Guid, Template_Version, Content_Object_Guid)
		SELECT	Template_Guid, @NextVersion, Content_Object_Guid
		FROM	Xtf_ContentLibrary_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
				
		INSERT INTO Xtf_Datasource_Dependency(Template_Guid, Template_Version, Data_Object_Guid)
		SELECT	Template_Guid, @NextVersion, Data_Object_Guid
		FROM	Xtf_Datasource_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
				
		INSERT INTO Xtf_Fragment_Dependency(Template_Guid, Template_Version, Fragment_Guid)
		SELECT	Template_Guid, @NextVersion, Fragment_Guid
		FROM	Xtf_Fragment_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
	COMMIT

GO














