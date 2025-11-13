require 'json'
require 'net/http'
require 'uri'
require 'base64'
require 'openssl'
require 'aws-sdk-s3'
require 'aws-sdk-bedrockruntime'


def lambda_handler(event:, context:)

  webhook_secret = ENV['Webhook_Key'];
  freshdesk_key = ENV['Freshdesk_Key'];
  freshdesk_url = ENV['Freshdesk_Domain'];
  @bucket_name = 'freshdesk-tickets'
  headers = event['headers'] || {}
  body = event['body'] || ""

    #verify jira webhook signature
    unless verify_signature(headers, body , webhook_secret)
        return {statusCode: 401, body: { error: 'invalid signature' }.to_json}
    end
  
  #Parse the webhook payload
  payload = JSON.parse(body)
  issue_key = payload.dig('issue', 'key')
  #custom field on Jira ticket where freshdesk link is displayed 
  freshdesk_link = payload.dig('issue', 'fields', 'customfield_XXXXXX')
  puts "Issue Key : #{issue_key}"
  #check if freshdesk link exists 
  if freshdesk_link.nil?
    puts "Freshdesk link not found in the payload."
  else
    puts "Freshdesk link: #{freshdesk_link}"
    freshdesk_ticketID = freshdesk_link.split('/').last
    puts "Freshdesk ticket ID: #{freshdesk_ticketID}"
  end

  get_freshdesk_convo(freshdesk_ticketID, freshdesk_key, freshdesk_url)
  get_freshdesk_ai_summary(freshdesk_ticketID)
  put_freshdesk_summary(issue_key, freshdesk_ticketID)

  { statusCode: 200, body: { received: true }}
end

          
def get_freshdesk_convo(freshdesk_ticketID, freshdesk_key, freshdesk_url)
  uri = URI("https://#{freshdesk_url}/api/v2/tickets/#{freshdesk_ticketID}?include=conversations")
  request = Net::HTTP::Get.new(uri)
  request.basic_auth(freshdesk_key, "X")
  request['Accept'] = 'application/json'
  
  freshdesk_response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
   http.request(request)
  end
  
  unless freshdesk_response.is_a?(Net::HTTPSuccess)
    return {statusCode: 500, body: {error:"freshdesk API request failed"}}
  end
  conversations = JSON.parse(freshdesk_response.body.force_encoding('UTF-8'))
  description = conversations['description_text']
  puts "description: #{description}"

  conversation_items = (conversations['conversations'] || []).map do |msg|
    {
      'user_id' => msg['user_id'],
      'body_text' => msg['body_text']
    }
    end

  ticket_data = {
    ticket_id: freshdesk_ticketID,
    description:  description,
    conversations: conversation_items
  }
  ticket_data_json = (ticket_data).to_json
  save_conversations_file(ticket_data_json, freshdesk_ticketID)
  
end

#save freshdesk conversations to a txt file in S3 bucket 
def save_conversations_file(data,freshdesk_ticketID)
  #enter aws region
  s3_client = Aws::S3::Client.new(region: 'xxxxxx')
  s3_client.put_object(
    bucket: @bucket_name,
    key: "freshdesk_convo_#{freshdesk_ticketID}.txt",
    body: data,
    content_type: 'text/plain; charset=utf-8'
  )
end
#use aws bedrock to get AI summary of the freshdesk ticket 
def get_freshdesk_ai_summary(freshdesk_ticketID)
  #enter aws region 
  s3_client = Aws::S3::Client.new(region: 'xxxxxx')
  freshdesk_file = s3_client.get_object(
    bucket: @bucket_name,
    key: "freshdesk_convo_#{freshdesk_ticketID}.txt"
  )
  #enter aws region
  bedrockruntime = Aws::BedrockRuntime::Client.new(region: 'xxxxxx')
  freshdesk_text = freshdesk_file.body.read.force_encoding('UTF-8').to_json
  response = bedrockruntime.invoke_model(
    body: {
      "messages" => [
        {
          "role" => "user",
          "content" => [
            {
              "text" => "Analyze this conversation and return a short concise summary of the conversation and key issues for troubleshooting team to understand in plain text only with no markdowns.\n\n#{freshdesk_text}"
            }
          ]
        }
      ]
    }.to_json,
    #select model 
    model_id: 'amazon.nova-lite-v1:0',
    accept: 'application/json',
    content_type: 'application/json'
)
response_body = JSON.parse(response.body.read.force_encoding('UTF-8'))
summary = response_body.dig("output", "message", "content", 0, "text")

#save ai summary to s3
s3_client.put_object(
  bucket: @bucket_name,
  key: "freshdesk_summary_#{freshdesk_ticketID}.txt",
  body: summary,
  content_type: 'text/plain; charset=utf-8'
)

end

#show summary on a Jira custom text field 
def put_freshdesk_summary(issue_key, freshdesk_ticketID)
  jira_username = ENV['Jira_Username'];
  jira_key = ENV['Jira_Key']
  jira_domain = ENV['Jira_Domain']
  #get freshdesk summary file
  s3_client = Aws::S3::Client.new(region: 'us-east-1')
  freshdesk_summary_file = s3_client.get_object(
    bucket: @bucket_name,
    key: "freshdesk_summary_#{freshdesk_ticketID}.txt"
  )
  freshdesk_text = freshdesk_summary_file.body.read.force_encoding('UTF-8')
  uri = URI("https://#{jira_domain}/rest/api/3/issue/#{issue_key}")
  body = {
    "fields" => {
      #enter custom field where ai summary will show 
      "customfield_xxxxx": {
       "content": [
        {
          "content":[
            {
            "text": freshdesk_text,
            "type": "text"
            } 
          ],
          "type": "paragraph"
        }
       ],
       "type": "doc",
       "version": 1
      }
    }
  }.to_json
  request = Net::HTTP::Put.new(uri)
  request.basic_auth(jira_username, jira_key)
  request['Accept'] = 'application/json'
  request['Content-Type'] = 'application/json'
  request.body = body

  jira_response = Net::HTTP.start(uri.hostname, uri.port, use_ssl:true) do |http|
   http.request(request)
  end
  unless jira_response.is_a?(Net::HTTPSuccess)
    return {statusCode: 500, body: {error:"jira API request failed"}}
  end
end

#compare function to verify jira webhook signature 
def secure_compare(a, b)
  return false unless a.bytesize == b.bytesize
  l = a.unpack "C#{a.bytesize}"
  res = 0
  b.each_byte { |byte| res |= byte ^ l.shift }
  res.zero?
end        
   
def verify_signature(headers, body, secret)
      
        # Get the signature from headers
        signature = headers['x-hub-signature']
        return false unless signature

        #get the signature from webhook
        method, received_sig = signature.split('=')
        method = method.downcase.strip
        received_sig = received_sig.strip
      
        #method should be sha256
        unless %w[sha256 sha1 sha512].include?(method)
          puts "Unsupported hash method: #{method}"
          return false
        end
        
        # Create HMAC using the secret key
       digest = OpenSSL::HMAC.hexdigest(method, secret, body)
        
        # Compare expected signature with received signature to authenticate the message
        puts "signature:  #{digest}\nReceived: #{received_sig}"
      
        if secure_compare(digest, received_sig)
          puts "Signature valid"
          true
        else
          puts "Signature mismatch"
          false
        end
  
end