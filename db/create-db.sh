#!/bin/bash

sqlite3 wallet.sqlite <<EOF
CREATE TABLE users (
                                ID INTEGER PRIMARY KEY AUTOINCREMENT,
                                username VARCHAR(255),
                                publickey TEXT,
                                privatekey TEXT,
                                useradmin INTEGER DEFAULT 0,
                                emergencyadmin INTEGER DEFAULT 0,
                                UNIQUE(username)
                        );
CREATE TABLE credentials (
                                ID INTEGER PRIMARY KEY AUTOINCREMENT,
                                description TEXT,
                                last_changed INTEGER,
                                expiry_weeks INTEGER,
                                insecure INTEGER DEFAULT 0,
                                encrypted TEXT
                        );
CREATE TABLE access (
                                ID INTEGER,
                                username VARCHAR(255),
                                grantedby VARCHAR(255),
                                is_owner INTEGER,
                                aeskey VARCHAR(255),
                                UNIQUE(ID, username)
                        );
CREATE TABLE alerts (
                                ID INTEGER,
                                alert TEXT
                        );
CREATE TABLE tags (
                                ID INTEGER,
                                tag VARCHAR(255)
                        );
EOF
