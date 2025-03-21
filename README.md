# Multi-Cloud, Multi-Account Static Website Infrastructure

This repository contains infrastructure as code for managing multiple static websites across different cloud providers and accounts, with support for multiple deployment stages (dev, preview, www) per website.

## Initiate directory structure

mkdir -p scripts infrastructure/{accounts/{example,another-example},modules/{static-website,backend},remote-state} websites/{example.com,example.org,another-example.com}/{dev,preview,www} tests/infrastructure

## Features

- Multi-cloud, Multi-account infrastructure management
