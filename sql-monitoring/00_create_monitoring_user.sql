USE [master];
GO

-- Create login for monitoring (run on server level)
CREATE LOGIN [monitoring_user] WITH PASSWORD = 'ChangeThisPassword123!';
GO

-- Connect to your target database first, then run:
USE [YourDatabaseName];
GO

CREATE USER [monitoring_user] FOR LOGIN [monitoring_user];
GO

GRANT VIEW SERVER STATE TO [monitoring_user];
GO

GRANT VIEW DATABASE STATE TO [monitoring_user];
GO

GRANT CONNECT SQL TO [monitoring_user];
GO