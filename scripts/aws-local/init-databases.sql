-- Creates the 6 service databases for the local "aws" profile stack (docker-compose.aws-local.yml).
-- Runs once, on the first start of an empty postgres volume. The owner is POSTGRES_USER.
CREATE DATABASE userdb;
CREATE DATABASE stationdb;
CREATE DATABASE ticketdb;
CREATE DATABASE orderdb;
CREATE DATABASE notificationdb;
CREATE DATABASE cronjobdb;
