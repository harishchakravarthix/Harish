truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.1.2');
go
ALTER TABLE dbo.Intelledox_User 
	ADD ResetPwdToken VARCHAR(20) NULL, 
		ResetPwdTokenExpiresOn_Utc Datetime NULL
GO
CREATE PROCEDURE [dbo].[spUser_UpdateResetPwdRequest]
	@UserGuid uniqueidentifier,
	@ResetPwdToken varchar(20),
	@ResetPwdTokenExpiresOn datetime

AS

BEGIN
	SET NOCOUNT ON;

	UPDATE Intelledox_User
	SET ResetPwdToken = @ResetPwdToken,
		ResetPwdTokenExpiresOn_Utc = @ResetPwdTokenExpiresOn
	WHERE User_Guid = @UserGuid;
END
GO
CREATE PROCEDURE [dbo].[spUser_GetUserByResetPwdToken]
	@ResetPwdToken varchar(20)
	
AS

BEGIN
	SELECT	*
	FROM	Intelledox_User
	WHERE	ResetPwdToken = @ResetPwdToken;
END
GO

-- Adding Display_Type column to Xtf_ContentLibrary_Dependency_Temp
CREATE TABLE [dbo].[Xtf_ContentLibrary_Dependency_Temp](
	[Template_Guid] [uniqueidentifier] NOT NULL,
	[Template_Version] [nvarchar](10) NOT NULL,
	[Content_Object_Guid] [uniqueidentifier] NOT NULL
) ON [PRIMARY]
GO
INSERT INTO [dbo].[Xtf_ContentLibrary_Dependency_Temp] ([Template_Guid], [Template_Version], [Content_Object_Guid])
SELECT [Template_Guid], [Template_Version], [Content_Object_Guid]
	FROM [dbo].[Xtf_ContentLibrary_Dependency]
GO
DROP TABLE [dbo].[Xtf_ContentLibrary_Dependency]
GO
CREATE TABLE [dbo].[Xtf_ContentLibrary_Dependency](
	[Template_Guid] [uniqueidentifier] NOT NULL,
	[Template_Version] [nvarchar](10) NOT NULL,
	[Content_Object_Guid] [uniqueidentifier] NOT NULL,
	[Display_Type] int NOT NULL	
) ON [PRIMARY]
GO
ALTER TABLE dbo.Xtf_ContentLibrary_Dependency ADD CONSTRAINT
	ContentLibrary_Guid_pk PRIMARY KEY CLUSTERED 
	(
	[Template_Guid],
	[Template_Version],
	[Content_Object_Guid],
	[Display_Type]
	)
GO
INSERT INTO [dbo].[Xtf_ContentLibrary_Dependency] ([Template_Guid], [Template_Version], [Content_Object_Guid], [Display_Type])
SELECT [Template_Guid], [Template_Version], [Content_Object_Guid], -1
	FROM [dbo].[Xtf_ContentLibrary_Dependency_Temp]
GO
DROP TABLE [dbo].[Xtf_ContentLibrary_Dependency_Temp]
GO

ALTER PROCEDURE [dbo].[spProject_UpdateDefinition] (
	@Xtf xml,
	@TemplateGuid uniqueidentifier,
	@EncryptedXtf varbinary(MAX)
)
AS
	SET ARITHABORT ON

	DECLARE @ExistingFeatureFlags int;
	DECLARE @FeatureFlags int;
	DECLARE @DataObjectGuid uniqueidentifier;
	DECLARE @XtfVersion nvarchar(10)

	BEGIN TRAN
		-- Feature detection --
		SET @FeatureFlags = 0
		SELECT @XtfVersion = Template.Template_Version, @ExistingFeatureFlags = ISNULL(Template.FeatureFlags, 0) FROM Template WHERE Template.Template_Guid = @TemplateGuid;

		-- Workflow
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/Workflow/State/Transition)') as ProjectXML(P))
		BEGIN
			--Looking for a specified transition from the start state
			IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/Workflow/State)') as StateXML(S)
					  CROSS APPLY S.nodes('(Transition)') as TransitionXML(T)
					  WHERE S.value('@ID', 'uniqueidentifier') = cast('11111111-1111-1111-1111-111111111111' as uniqueidentifier)
					  AND (T.value('@SendToType', 'int') = 0 or T.value('@SendToType', 'int') IS NULL))
			BEGIN
				SET @FeatureFlags = @FeatureFlags | 256;
			END
			ELSE
			BEGIN
				SET @FeatureFlags = @FeatureFlags | 1;
			END
		END

		-- Data source
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 2		-- Data field
						OR Q.value('@TypeId', 'int') = 9	-- Data table
						OR Q.value('@TypeId', 'int') = 12	-- Data list
						OR Q.value('@TypeId', 'int') = 14)	-- Data source
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 2;

			INSERT INTO Xtf_Datasource_Dependency(Template_Guid, Template_Version, Data_Object_Guid)
			SELECT DISTINCT @TemplateGuid,
					@XtfVersion,
					Q.value('@DataObjectGuid', 'uniqueidentifier')
			FROM 
				@Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question)') as QuestionXML(Q)
			WHERE Q.value('@DataObjectGuid', 'uniqueidentifier') is not null
				AND Q.value('@DataServiceGuid', 'uniqueidentifier') <> '6a4af944-0563-4c95-aba1-ddf2da4337b1'
				AND (SELECT  COUNT(*)
				FROM    Xtf_Datasource_Dependency 
				WHERE   Template_Guid = @TemplateGuid
				AND     Template_Version = @XtfVersion 
				AND		Data_Object_Guid = Q.value('@DataObjectGuid', 'uniqueidentifier')) = 0
			
		END

		-- Content library
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 11
						AND Q.value('@DisplayType', 'int') = 8) -- Existing content item
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 4;
		END
		
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 11
						AND Q.value('@DisplayType', 'int') = 4) -- Search
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 8;
		END

		IF EXISTS(SELECT 1 FROM Xtf_ContentLibrary_Dependency
			WHERE	Xtf_ContentLibrary_Dependency.Template_Guid = @TemplateGuid AND
					Xtf_ContentLibrary_Dependency.Template_Version = @XtfVersion)
		BEGIN
			DELETE FROM Xtf_ContentLibrary_Dependency
			WHERE	Xtf_ContentLibrary_Dependency.Template_Guid = @TemplateGuid AND
					Xtf_ContentLibrary_Dependency.Template_Version = @XtfVersion;
		END

		INSERT INTO Xtf_ContentLibrary_Dependency(Template_Guid, Template_Version, Content_Object_Guid, Display_Type)
		SELECT DISTINCT @TemplateGuid, @XtfVersion, Content_Object_Guid, Display_Type
		FROM (
			SELECT C.value('@Id', 'uniqueidentifier') as Content_Object_Guid,
				-1 AS Display_Type
			FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question/Answer/ContentItem)') as ContentItemXML(C)
			UNION
			SELECT Q.value('@ContentItemGuid', 'uniqueidentifier'),
				Q.value('@DisplayType', 'int') AS Display_Type
			FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question)') as QuestionXML(Q)
			WHERE Q.value('@ContentItemGuid', 'uniqueidentifier') is not null) Content

		-- Address
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 1)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 16;
		END

		-- Rich text
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 19)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 64;
		END
			
		-- Custom Question
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 22)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 128;
		END

		-- Fragments
		IF EXISTS(SELECT 1 FROM Xtf_Fragment_Dependency
					WHERE	Xtf_Fragment_Dependency.Template_Guid = @TemplateGuid AND
							Xtf_Fragment_Dependency.Template_Version = @XtfVersion)
		BEGIN
			DELETE FROM Xtf_Fragment_Dependency
			WHERE	Xtf_Fragment_Dependency.Template_Guid = @TemplateGuid AND
					Xtf_Fragment_Dependency.Template_Version = @XtfVersion;
		END
		
		INSERT INTO Xtf_Fragment_Dependency(Template_Guid, Template_Version, Fragment_Guid)
		SELECT DISTINCT @TemplateGuid, @XtfVersion, Fragment_Guid
		FROM (
			SELECT fp.value('@ProjectGuid', 'uniqueidentifier') as Fragment_Guid
			FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as PageFragmentXML(fp)
			WHERE fp.value('@ProjectGuid', 'uniqueidentifier') IS NOT NULL
			UNION
			SELECT fn.value('@ProjectGuid', 'uniqueidentifier')
			FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Layout//Fragment)') as NodeFragmentXML(fn)
			WHERE fn.value('@ProjectGuid', 'uniqueidentifier') IS NOT NULL) Fragments

		IF EXISTS(SELECT 1 FROM Xtf_Fragment_Dependency WHERE Template_Guid = @TemplateGuid AND Template_Version = @XtfVersion)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 512;
		END

		IF @EncryptedXtf IS NULL
		BEGIN
			UPDATE	Template 
			SET		Project_Definition = @XTF,
					FeatureFlags = @FeatureFlags,
					EncryptedProjectDefinition = NULL
			WHERE	Template_Guid = @TemplateGuid;
		END
		ELSE
		BEGIN
			UPDATE	Template 
			SET		EncryptedProjectDefinition = @EncryptedXtf,
					FeatureFlags = @FeatureFlags,
					Project_Definition = NULL
			WHERE	Template_Guid = @TemplateGuid;
		END

		-- Updating project group feature flags is expensive, only do it if our flags have changed
		-- or we contain project fragments (could have been added or removed)
		IF @ExistingFeatureFlags <> @FeatureFlags OR (@FeatureFlags & 512) = 512
		BEGIN
			EXEC spProjectGroup_UpdateFeatureFlags @ProjectGuid=@TemplateGuid;
		END
	COMMIT
GO

CREATE PROCEDURE [dbo].[spProject_DependentContentItems] (
	@ProjectGuid uniqueidentifier,
	@Version nvarchar(10)
)
AS
		SELECT DISTINCT Content_Item.ContentItem_Guid,
			ContentData_Binary.ContentData_Version,
			Content_Item.NameIdentity,
			ContentData_Binary.FileType
		FROM Xtf_ContentLibrary_Dependency
			INNER JOIN Content_Item ON Xtf_ContentLibrary_Dependency.Content_Object_Guid = Content_Item.ContentItem_Guid
			INNER JOIN ContentData_Binary ON Content_Item.ContentData_Guid = ContentData_Binary.ContentData_Guid
			INNER JOIN 	(SELECT Template.Template_Guid
						FROM Template
						WHERE Template.Template_Guid = @ProjectGuid
							AND Template.Template_Version = @Version
					UNION
						SELECT Template_Version.Template_Guid
						FROM Template_Version
						WHERE Template_Version.Template_Guid = @ProjectGuid
							AND Template_Version.Template_Version = @Version) TemplateVersion
				ON TemplateVersion.Template_Guid = Xtf_ContentLibrary_Dependency.Template_Guid
		WHERE Xtf_ContentLibrary_Dependency.Display_Type = '8'
GO









































