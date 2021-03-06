truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.1.10');
go

ALTER VIEW [dbo].[vwSubmissions]
AS

	SELECT	Template_Log.Log_Guid,
			Template.Template_Id,
			Template_Log.DateTime_Finish AS _Completion_Time_UTC,
			Intelledox_User.Username AS _Username,
			CASE WHEN Template_Log.CompletionState = 3 THEN 1 ELSE 0 END AS _Completed,
			CASE WHEN Template_Log.CompletionState = 2 THEN 1 ELSE 0 END AS _WorkflowInProgress,
			(SELECT TOP 1 LatestState.StateName
				FROM ActionListState LatestState
				WHERE LatestState.ActionListId = ActionListState.ActionListId
				ORDER BY LatestState.DateCreatedUtc DESC) AS _CurrentState
	FROM	Template_Log 
			INNER JOIN Template_Group ON Template_Group.Template_Group_Id = Template_Log.Template_Group_Id
			INNER JOIN Template ON Template.Template_Guid = Template_Group.Template_Guid
			LEFT JOIN Intelledox_User ON Intelledox_User.User_ID = Template_Log.User_Id
			LEFT JOIN ActionListState ON Template_Log.ActionListStateId = ActionListState.ActionListStateId
	WHERE Template_Log.CompletionState = 3
		OR (Template_Log.CompletionState = 2
			AND Template_Log.DateTime_Finish IN (SELECT MAX(tl.DateTime_Finish)
				FROM Template_Log tl
					INNER JOIN ActionListState als On tl.ActionListStateId = als.ActionListStateId
						AND als.ActionListId = ActionListState.ActionListId))

GO
