namespace :coverline do
  desc "Development only: create a fresh webhook API key for the first organization and print it"
  task dev_api_key: :environment do
    abort "Not in production." if Rails.env.production?
    org = Organization.first or abort "No organization. Run bin/rails db:seed first."
    puts org.generate_api_key!
    warn "(That key replaced any previous one for #{org.name}.)"
  end
end
