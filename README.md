## Project Overview:

This AWS Lambda function, written in Ruby, automatically summarizes Freshdesk support tickets to assist engineers with troubleshooting. The function is triggered when a new troubleshooting ticket is created in Jira and generates an AI-powered summary using AWS Bedrock based on the ticket's associated Freshdesk conversation. By automating the summarization process, this workflow helps engineers quickly understand the context of customer issues without manually reviewing the full conversation history.

## Workflow
<img width="578" height="492" alt="Screen Shot 2026-03-12 at 5 57 21 PM" src="https://github.com/user-attachments/assets/6f654205-a7c2-4e1a-918a-0a879aa2b547" />

## Tools
Programming Language: Ruby

AWS Services : AWS Lambda, AWS Bedrock, S3 Buckets, API Gateway

APIs & Integrations: Jira REST API, Freshdesk API, Jira Webhooks

Version Control: Git, GitHub



