truncate table dbversion;
go
insert into dbversion(dbversion) values ('10.0.40');
GO

ALTER PROCEDURE [dbo].[spLog_GetSubmissionLog]
	@StartDateUTC datetime, 
	@BusinessUnitGuid uniqueidentifier
AS
BEGIN
	SELECT Template_Group.Template_Group_ID,
		Template_Log.DateTime_Finish,
		Template_Log.Log_Guid,
		Template_Log.CompletionState,
		Template.Template_Guid
	FROM Template_Log
		LEFT JOIN Intelledox_User ON Template_Log.User_ID = Intelledox_User.User_ID
		LEFT JOIN Intelledox_UserDeleted ON Template_Log.User_ID = Intelledox_UserDeleted.User_ID
		LEFT JOIN Template_Group ON Template_Log.Template_Group_ID = Template_Group.Template_Group_ID
		LEFT JOIN Template ON Template.Template_Guid = Template_Group.Template_Guid
	WHERE DateTime_Finish > @StartDateUTC
		AND (Intelledox_User.Business_Unit_Guid = @BusinessUnitGuid
			OR Intelledox_UserDeleted.BusinessUnitGuid = @BusinessUnitGuid)
		AND (CompletionState = 2 -- Workflow State Completed
			OR CompletionState = 3) -- Completed
		AND RunID <> '00000000-0000-0000-0000-000000000000'; -- Watch Folder Scheduled Jobs
END
GO
