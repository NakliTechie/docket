namespace :docket do
  namespace :privacy do
    desc "Erase a contact's direct content unless an active legal hold blocks it"
    task :erase_contact, %i[tenant_slug contact_id] => :environment do |_task, args|
      tenant = Tenant.find_by!(slug: args.fetch(:tenant_slug))
      expected = "ERASE CONTACT #{args.fetch(:contact_id)} FROM #{tenant.slug}"
      abort "Refusing: set CONFIRM_PRIVACY_ERASURE=#{expected.inspect}" unless
        ENV["CONFIRM_PRIVACY_ERASURE"] == expected

      result = ActsAsTenant.with_tenant(tenant) do
        contact = Contact.with_deleted.find(args.fetch(:contact_id))
        Privacy::EraseContact.call(contact: contact, requested_by: nil)
      end
      puts "Erasure complete: #{result.request.erasure_token} (#{result.summary.to_json})"
    end
  end
end
