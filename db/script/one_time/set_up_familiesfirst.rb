# Families First (VT) Launch
# Company name: Families First
# Domain: familiesfirstvt.com
# Stub: familiesfirst
# Launch: Wednesday 28 October 2015 14:00 EST

# Launch parameters - fully connected, Ripple50/50 for self and others - Comments ON
#
# SurveySeries ID 2 - Ripple 50/50-up - Ripple 50 questions all at once
#
# <SurveySeries id: 2, created_at: "2015-07-28 11:26:54", updated_at: "2015-07-28 11:26:54", 
#  name: "Ripple 50/50-up", description: "Ripple 50 questions all at once", 
#  default_config: {"for_self"=>true, "allow_comments"=>false, "hours_between_surveys"=>8760}, 
#  parent_characteristic_id: 1>
#
# Will transition to Ripple50/5 after first week

puts "Setting up Families First VT"

# Company setup details
thename = 'Families First' # Name of the co as it should appear in Ripple emails etc.
thedomain = 'familiesfirstvt.com' # Co's primary email domain e.g. theboss@thedomain
thestub = 'familiesfirst' # Stub to be used e.g. thestub.ripplecrew.com

begin
  ActiveRecord::Base.transaction do

    # Create The Boss as a prospect
    theboss = Ripple::OnboardUser.create_prospect('Julie', 'Cunningham', 'juliecfamilies@myfairpoint.net', thename)

    # Create The Company from the maven, create a subscription plan
    onboarder = Ripple::OnboardUser.new(theboss)
    thecompany = onboarder.create_company(thename, thedomain, thestub)
    subscription = thecompany.subscriptions.active_state.first
    company_subscriber = Ripple::Subscription::CompanySubscription.new(subscription)

    # Apply company ettings
    thecompany.set_config(:consultant_mode, true) # members cannot invite new people
    thecompany.set_config(:reminder_hour, 8) # Eastern time mornings

    # Set up the CompanySurveySeries for go-live surveys only
    thecompany.use_series(2, {for_self: true, allow_comments: false, hours_between_surveys: 99999, create_manually: true})
    thecompany.use_series(2, {for_self: false, allow_comments: true, hours_between_surveys: 99999, create_manually: true})

    # Create and register additional users
    # Format: array of arrays of the form [ 'first_name', 'last_name', 'email' ]

    team1_names = [
      [ 'Sue',       'Graup',     'sue@familiesfirstvt.com' ],
      [ 'Greg',      'Masterson', 'greg@familiesfirstvt.com' ],
      [ 'Stephanie', 'Salasin',   'steph@familiesfirstvt.com' ],
      [ 'Trisha',    'Crocker',   'trisha@familiesfirstvt.com' ],
      [ 'Lauren',    'Herlocker', 'laurenrose@familiesfirstvt.com' ],
      [ 'Jayinee',   'Adhvaryu',  'jayinee@familiesfirstvt.com' ],
      [ 'Jenny',     'Holler',    'jenny@familiesfirstvt.com' ],
      [ 'John',      'Jamison',   'john@familiesfirstvt.com' ],
      [ 'Marybeth',  'Kover',     'marybeth@familiesfirstvt.com' ],
      [ 'Joshua',    'Kussius',   'joshua@familiesfirstvt.com' ],
      [ 'Katie',     'McCarthy',  'katie@familiesfirstvt.com' ],
      [ 'Ashley',    'McHale',    'ashleymchale@yahoo.com' ],
      [ 'David',     'Wheeler',   'david@familiesfirstvt.com' ]
    ]

    teams = {}
    [team1_names].each_with_index do |team, i|
      teams[i+1] = []
      team.each do |name|
        puts "Creating #{name[2]}"
        tmp_password = SecureRandom.password
        u = User.create!({
          first_name: name[0],
          last_name: name[1],
          email: name[2],
          company: thecompany,
          type: User::RIPPLER,
          state: User::ACTIVE,
          confirmed_at: Time.now,
          password: tmp_password,
          password_confirmation: tmp_password,
          last_reminded_at: Ripple::Time::WHEN_ROBOTS_RULE # suppress reminders
        })
        teams[i+1] << u
        company_subscriber.register_user(u)
      end
    end

    # Include The Boss on a team too
    teams[1] << theboss

    # Connect SurveyPlans but DO NOT send intro emails
    puts "Connecting..."
    connector = Ripple::CompanyConnector.new(thecompany, nil, thecompany.company_survey_series.for_others.active.first)
    connector.join_groups(teams[1], teams[1])

    # connect everyone for self-surveys & set reminder times
    connector = Ripple::CompanyConnector.new(thecompany, nil, thecompany.company_survey_series.for_self.active.first)
    thecompany.users.each do |u|
      connector.join_self(u)
    end
  end
rescue
  puts 'Error setting up Families First VT.  Rolled back.'
else
  puts "Upgrading subscription..."
  thecompany = Company.find_by_stub(thestub)
  cs = Ripple::Subscription::CompanySubscription.new(thecompany.subscriptions.active)
  cs.change_plan('enterprise_1')

  # Generate surveys, but DO NOT remind
  puts "Generating surveys..."
  thecompany = Company.find_by_stub(thestub)
  thecompany.users.active.each { |u| Resque.enqueue(Job::CreateUserSurveys, u.id) }
  puts "Finished generating surveys"

  puts "Sending Activation Emails"
  # Note: Maven gets an email saying that they signed themselves up
  thecompany = Company.find_by_stub(thestub)
  thecompany.all_members.active.each do |u|
    puts "Activating #{u.email}"
    CustomDeviseMailer.maven_signed_you_up(u.id).deliver
    u.update_attributes!(last_reminded_at: Time.now)
  end
  
  "Script completed at #{Time.now}"
end
