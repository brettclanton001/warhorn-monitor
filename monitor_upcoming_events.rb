require 'net/http'
require 'net/https'
require 'uri'
require 'json'
require 'date'
require 'redis'
require 'airbrake-ruby'

def logger(message)
  puts message
end

logger 'Script Starting'

def fetch_env(name)
  raise "#{name} not found" unless ENV[name]
  ENV[name]
end

AIRBRAKE_PROJECT_ID = fetch_env('AIRBRAKE_PROJECT_ID').freeze
AIRBRAKE_API_KEY = fetch_env('AIRBRAKE_API_KEY').freeze
NOTIFICATION_EMAIL = fetch_env('NOTIFICATION_EMAIL').freeze
MAILGUN_DOMAIN = fetch_env('MAILGUN_DOMAIN').freeze
MAILGUN_API_KEY = fetch_env('MAILGUN_API_KEY').freeze
REDIS_URL = fetch_env('REDIS_URL').freeze
WARHORN_EVENT = fetch_env('WARHORN_EVENT').freeze
WARHORN_EVENT_ID = fetch_env('WARHORN_EVENT_ID').freeze

# Airbrake Error Monitoring
Airbrake.configure do |c|
  c.project_id = AIRBRAKE_PROJECT_ID
  c.project_key = AIRBRAKE_API_KEY
end

# Mailgun Integration
def send_notification(message)
  uri = URI.parse("https://api.mailgun.net/v2/#{MAILGUN_DOMAIN}/messages")
  data = {
    'to': NOTIFICATION_EMAIL,
    'from': [
      'robot',
      MAILGUN_DOMAIN
    ].join('@'),
    'subject': 'Warhorn Monitor Notification',
    'text': message
  }
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri)
  request.basic_auth("api", MAILGUN_API_KEY)
  request.set_form_data(data)
  http.request(request)
end

# Redis Integration
def create_key_and_notify(uuid)
  redis = Redis.new(url: REDIS_URL)
  unless redis.exists(uuid) == 1
    logger 'processing new event..'
    link = "https://warhorn.net/events/#{WARHORN_EVENT}/schedule/sessions/#{uuid}"
    message = "New event found: #{link}"
    send_notification(message)
    redis.set(uuid, Time.now)
  else
    logger 'event already processed'
  end
end

# Warhorn Query
def warhorn_upcoming_events
  start_date = Date.today
  end_date = start_date + 60
  uri = URI('https://warhorn.net/api/event-session-listings')
  params = {
    "filter[eventId]": WARHORN_EVENT_ID,
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
data = warhorn_upcoming_events["data"]
logger "#{data.count} events found"
data.each do |event|
  logger "event #{event["attributes"]["uuid"]} found"
  create_key_and_notify(event["attributes"]["uuid"])
end
