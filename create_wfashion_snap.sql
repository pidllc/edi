CREATE DATABASE wfashion_snapshot
ON (NAME = wfData, FILENAME = 'F:\SQLDATA\wfashion_snapshot.smf')
AS SNAPSHOT = wfashion;