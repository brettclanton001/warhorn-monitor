require 'net/http'
require 'net/https'  
require 'uri'
require 'json'
require 'date'
require 'redis'
require 'airbrake-ruby'

# Airbrake Error Monitoring
Airbrake.configure do |c|
  c.project_id = ENV['AIRBRAKE_PROJECT_ID']
  c.project_key = ENV['AIRBRAKE_API_KEY']
end

# Mailgun Integration
def send_notification(message)
	uri = URI.parse("https://api.mailgun.net/v2/#{ENV['MAILGUN_DOMAIN']}/messages")
	data = {
		'to': ENV['NOTIFICATION_EMAIL'],  
	    'from': [
	    	'robot',
	    	ENV['MAILGUN_DOMAIN']
	    ].join('@'),
	    'subject': 'Warhorn Monitor Notification',
	    'text': message
	}
	http = Net::HTTP.new(uri.host, uri.port)  
	http.use_ssl = true
	request = Net::HTTP::Post.new(uri.request_uri)  
	request.basic_auth("api", ENV['MAILGUN_API_KEY'])  
	request.set_form_data(data)
	response = http.request(request)
end

# Redis Integration
def create_key_and_notify(uuid)
	redis = Redis.new(url: ENV['REDIS_URL'])
	unless redis.exists(uuid) == 1
		link = "https://warhorn.net/events/dd-al-the-wyverns-tale/schedule/sessions/#{uuid}"
		message = "New event found: #{link}"
		send_notification(message)
		redis.set(uuid, Time.now)
	end
end

# Warhorn Query
def warhorn_upcoming_events
	start_date = Date.today
	end_date = start_date + 60
	uri = URI('https://warhorn.net/api/event-session-listings')
	params = {
		"filter[eventId]": 7299,
		"filter[status]": %w(
			canceled
			published
		),
		"filter[startsAtOrAfter]": start_date,
		"filter[startsBefore]": end_date,
		"include": %w(
			campaignMode
			scenario.campaign.gameSystem
			scenario.campaignTags
			scenario.factions
			scenario.gameSystem
			slot.venue
		),
		"page[number]": 1,
		"page[size]": 100,
		"sort": "dates"
	}
	uri.query = URI.encode_www_form(params)
	response = Net::HTTP.get(uri)
	JSON.parse(response)
end

# Main Script
warhorn_upcoming_events["data"].each do |event|
	create_key_and_notify(event["attributes"]["uuid"])
end
