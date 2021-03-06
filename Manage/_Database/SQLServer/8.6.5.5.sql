truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.6.5.5');
go

ALTER VIEW [dbo].[vwProjectDetails]
AS
SELECT  t.Template_ID, t.Name, t.Template_Type_ID, t.Template_Guid, t.Template_Version, t.Import_Date, t.HelpText, 
        t.Business_Unit_GUID, t.Supplier_Guid, t.Project_Definition, t.Modified_Date, t.Modified_By, t.Comment, t.LockedByUserGuid, t.FeatureFlags, 
        t.IsMajorVersion, tg.Template_Group_ID, t.Name AS GroupName, tg.Template_Group_Guid, tg.HelpText AS GroupHelpText, tg.AllowPreview, tg.PostGenerateText, 
        tg.UpdateDocumentFields, tg.EnforceValidation, tg.WizardFinishText, tg.EnforcePublishPeriod, tg.PublishStartDate, tg.PublishFinishDate, 
        tg.HideNavigationPane, tg.Template_Guid AS Expr3, tg.Template_Version AS Expr4, tg.Layout_Guid, tg.Layout_Version, tg.Folder_Guid
FROM    dbo.Template AS t INNER JOIN
        dbo.Template_Group AS tg ON tg.Template_Guid = t.Template_Guid

GO


ALTER PROCEDURE [dbo].[spProject_TryLockProject]
	@ProjectGuid uniqueidentifier,
	@UserGuid uniqueidentifier
	
AS

	BEGIN TRAN
	
		--check for a deleted project
		IF NOT EXISTS(SELECT 1 FROM Template WHERE Template_Guid = @ProjectGuid) 
			SELECT ''
		ELSE
		BEGIN
			IF NOT EXISTS(SELECT 1 FROM Template INNER JOIN Intelledox_User on template.LockedByUserGuid = Intelledox_User.User_Guid WHERE Template_Guid = @ProjectGuid)
			BEGIN
				UPDATE	Template
				SET		LockedByUserGuid = @UserGuid
				WHERE	Template_Guid = @ProjectGuid;
				
				SELECT ''				
			END
			ELSE
			BEGIN
				SELECT	Username 
				FROM	Intelledox_User 
						INNER JOIN Template ON Intelledox_User.User_Guid = Template.LockedByUserGuid
				WHERE	Template_Guid = @ProjectGuid						
			END
		END
		
	COMMIT
	
GO
