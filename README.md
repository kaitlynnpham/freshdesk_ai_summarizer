This Lambda function, written in Ruby, automatically summarizes Freshdesk tickets to assist with troubleshooting.
It is triggered whenever a new Jira troubleshooting ticket is created and uses data from both Freshdesk and AWS Bedrock to generate a concise summary of the issue.

Trigger:
The function is invoked by a Jira webhook when a new troubleshooting ticket is created.

Fetch Freshdesk Data:
It retrieves the Freshdesk link from the Jira ticket and calls the Freshdesk API to gather the full conversation history.

Store in S3:
The conversation data is saved as a .txt file in an Amazon S3 bucket.

Summarize via Bedrock:
The text file is analyzed using an AI model from AWS Bedrock to generate a concise summary of the ticket’s key issues.

Update Jira Ticket:
The summary is sent back to Jira via its REST API and added to a custom text field on the same ticket.
