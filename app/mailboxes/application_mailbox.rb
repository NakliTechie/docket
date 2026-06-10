class ApplicationMailbox < ActionMailbox::Base
  routing all: :cases
end
