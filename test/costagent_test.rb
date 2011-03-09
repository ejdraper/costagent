require "rubygems"
require "test/unit"
require "shoulda"
require "mocha"
require File.join(File.expand_path(File.dirname(__FILE__)), "..", "lib", "costagent")

class CostAgentTest < Test::Unit::TestCase
  class TestCache
    def initialize
      @cache = {}
    end

    def cache_key(subdomain, resource, identifier)
      "#{subdomain}_#{resource}_#{identifier}"
    end

    def exists?(subdomain, resource, identifier)
      @cache.keys.include?(self.cache_key(subdomain, resource, identifier))
    end

    def get(subdomain, resource, identifier)
      @cache[self.cache_key(subdomain, resource, identifier)]
    end

    def set(subdomain, resource, identifier, value)
      @cache[self.cache_key(subdomain, resource, identifier)] = value
    end
  
    def clear!
      @cache = {}
    end
  end

  CostAgent.cache_provider = TestCache.new

  context "initializing costagent" do
    should "raise error if no subdomain is specified" do
      ex = assert_raises RuntimeError do
        CostAgent.new("", "username", "password")
      end
      assert_equal "No subdomain configured!", ex.message
    end

    should "raise error if no username is specified" do
      ex = assert_raises RuntimeError do
        CostAgent.new("subdomain", "", "password")
      end
      assert_equal "No username configured!", ex.message
    end

    should "raise error if no password is specified" do
      ex = assert_raises RuntimeError do
        CostAgent.new("subdomain", "username", "")
      end
      assert_equal "No password configured!", ex.message
    end

    should "not raise error with valid inputs" do
      costagent = CostAgent.new("subdomain", "username", "password")
      assert_equal "subdomain", costagent.subdomain
      assert_equal "username", costagent.username
      assert_equal "password", costagent.password
    end
  end

  context "request to query projects" do
    setup do
      CostAgent.cache_provider.clear!
      setup_projects_test_response
    end
    
    should "parse response for projects" do
      projects = @costagent.projects
      assert_equal 2, projects.length
      assert_equal 1, projects.first.id
      assert_equal "test project", projects.first.name
      assert_equal "GBP", projects.first.currency
      assert_equal 45.0, projects.first.hourly_billing_rate
      assert_equal 360.0, projects.first.daily_billing_rate
      assert_equal 8.0, projects.first.hours_per_day
      assert_equal 2, projects.last.id
      assert_equal "test project 2", projects.last.name
      assert_equal "GBP", projects.last.currency
      assert_equal 50.0, projects.last.hourly_billing_rate
      assert_equal 400.0, projects.last.daily_billing_rate
      assert_equal 8.0, projects.last.hours_per_day
    end
  end

  context "request to query all projects" do
    setup do
      CostAgent.cache_provider.clear!
      setup_projects_test_response("all")
    end
    
    should "parse response for projects" do
      projects = @costagent.projects("all")
      assert_equal 2, projects.length
      assert_equal 1, projects.first.id
      assert_equal 1, projects.first.contact_id
      assert_equal "test project", projects.first.name
      assert_equal "GBP", projects.first.currency
      assert_equal 45.0, projects.first.hourly_billing_rate
      assert_equal 360.0, projects.first.daily_billing_rate
      assert_equal 8.0, projects.first.hours_per_day
      assert_equal 2, projects.last.id
      assert_equal 1, projects.last.contact_id
      assert_equal "test project 2", projects.last.name
      assert_equal "GBP", projects.last.currency
      assert_equal 50.0, projects.last.hourly_billing_rate
      assert_equal 400.0, projects.last.daily_billing_rate
      assert_equal 8.0, projects.last.hours_per_day
    end

    should "lookup a single project" do
      project = @costagent.project(1)
      assert_equal 1, project.id
      assert_equal "test project", project.name
      assert_equal "GBP", project.currency
      assert_equal 45.0, project.hourly_billing_rate
    end
  end

  context "request to query timeslips" do
    setup do
      CostAgent.cache_provider.clear!
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
      setup_tasks_test_response(1)
    end

    should "parse response for timeslips" do
      timeslips = @costagent.timeslips(@start, @end)
      assert_equal 2, timeslips.length
      assert_equal 1, timeslips.first.id
      assert_equal 1, timeslips.first.project.id
      assert_equal 1, timeslips.first.task.id
      assert_equal 10.0, timeslips.first.hours
      assert_equal 450.0, timeslips.first.cost
      assert_equal "test comment", timeslips.first.comment
      assert_equal "Locked", timeslips.first.status
      assert_equal 2, timeslips.last.id
      assert_equal 1, timeslips.last.project.id
      assert_equal 1, timeslips.last.task.id
      assert_equal 8.0, timeslips.last.hours
      assert_equal 360.0, timeslips.last.cost
      assert_equal "test comment", timeslips.last.comment
      assert_equal "Locked", timeslips.last.status
    end
  end

  context "request to query tasks for a given project" do
    setup do
      CostAgent.cache_provider.clear!
      setup_projects_test_response("all")
      setup_tasks_test_response(1)
    end

    should "parse response for tasks" do
      tasks = @costagent.tasks(@costagent.projects("all").first.id)
      assert_equal 2, tasks.length
      assert_equal 1, tasks.first.id
      assert_equal 1, tasks.first.project.id
      assert_equal "Development", tasks.first.name
      assert_equal 45.0, tasks.first.hourly_billing_rate
      assert_equal 360.0, tasks.first.daily_billing_rate
      assert_equal true, tasks.first.billable
      assert_equal 2, tasks.last.id
      assert_equal 1, tasks.last.project.id
      assert_equal "Design", tasks.last.name
      assert_equal 0.0, tasks.last.hourly_billing_rate
      assert_equal 0.0, tasks.last.daily_billing_rate
      assert_equal false, tasks.last.billable
    end
  end

  context "request to query time worked" do
    setup do
      CostAgent.cache_provider.clear!
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
      setup_tasks_test_response(1)
    end

    should "return the right time for the timeslips" do
      assert_equal 18.0, @costagent.worked(@start, @end)
    end
  end
  
  context "request to query amount earnt" do
    setup do
      CostAgent.cache_provider.clear!
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
      setup_tasks_test_response(1)
    end

    should "return the right amount for the timeslips" do
      assert_equal 810.0, @costagent.earnt(@start, @end)
    end
  end

  context "request to query USD exchange rate" do
    setup do
      CostAgent.cache_provider.clear!
    end

    should "parse response from xe.com" do
      Kernel.expects(:open).with("http://www.xe.com").returns("<a id=\"USDGBP31\">1.48095</a>")
      assert_equal 1.48095, CostAgent.usd_rate
    end

    should "return default value if xe.com raises an error" do
      CostAgent.send(:class_variable_set, "@@rate", nil)
      Kernel.expects(:open).raises("random test error")
      assert_equal 1.6, CostAgent.usd_rate
    end
  end

  context "request to verify credentials and query user details" do
    setup do
      CostAgent.cache_provider.clear!
      setup_test_response("", "verify", nil, {:user_id => 12345, :user_permission_level => 8, :company_type => "UkSoleTrader"})
    end
    
    should "make a call to the FA API" do
      assert_equal 12345, @costagent.user.id
      assert_equal 8, @costagent.user.permissions
      assert_equal "UkSoleTrader", @costagent.user.company_type
    end
  end

  context "request to query all invoices" do
    setup do
      CostAgent.cache_provider.clear!
      setup_invoices_test_response
      setup_projects_test_response("all")
    end
    
    should "parse response for invoices" do
      invoices = @costagent.invoices
      assert_equal 1, invoices.length
      assert_equal 1, invoices.first.id
      assert_equal "test invoice", invoices.first.description
      assert_equal "TEST001", invoices.first.reference
      assert_equal 100.0, invoices.first.amount
      assert_equal "Sent", invoices.first.status
      assert_equal 1, invoices.first.project_id
      assert_equal 1, invoices.first.items.first.id
      assert_equal 1, invoices.first.items.first.invoice_id
      assert_equal 1, invoices.first.items.first.project_id
      assert_equal "Hours", invoices.first.items.first.item_type
      assert_equal "test invoice item", invoices.first.items.first.description
      assert_equal 45.0, invoices.first.items.first.price
      assert_equal 12.0, invoices.first.items.first.quantity
      assert_equal 540.0, invoices.first.items.first.cost
    end

    should "lookup a single invoice" do
      invoice = @costagent.invoice(1)
      assert_equal 1, invoice.id
      assert_equal "test invoice", invoice.description
      assert_equal "TEST001", invoice.reference
      assert_equal 100.0, invoice.amount
      assert_equal "Sent", invoice.status
      assert_equal 1, invoice.project_id
      assert_equal 1, invoice.items.first.id
      assert_equal 1, invoice.items.first.invoice_id
      assert_equal 1, invoice.items.first.project_id
      assert_equal "Hours", invoice.items.first.item_type
      assert_equal "test invoice item", invoice.items.first.description
      assert_equal 45.0, invoice.items.first.price
      assert_equal 12.0, invoice.items.first.quantity
      assert_equal 540.0, invoice.items.first.cost
    end
  end

  context "request to query all contacts" do
    setup do
      CostAgent.cache_provider.clear!
      setup_contacts_test_response
      setup_projects_test_response("all")
    end
    
    should "parse response for contacts" do
      contacts = @costagent.contacts
      assert_equal 1, contacts.length
      assert_equal 1, contacts.first.id
      assert_equal 2, contacts.first.projects.length
      assert_equal "Test Ltd", contacts.first.organisation_name
      assert_equal "Test", contacts.first.first_name
      assert_equal "Testerson", contacts.first.last_name
      assert_equal "Test Address 1", contacts.first.address1
      assert_equal "Test Address 2", contacts.first.address2
      assert_equal "Test Address 3", contacts.first.address3
      assert_equal "Test Town", contacts.first.town
      assert_equal "Test Region", contacts.first.region
      assert_equal "United Kingdom", contacts.first.country
      assert_equal "Test Postcode", contacts.first.postcode
      assert_equal "01234 567890", contacts.first.phone_number
      assert_equal "test@test.com", contacts.first.email
      assert_equal "test@test.com", contacts.first.billing_email
      assert_equal true, contacts.first.contact_name_on_invoices
      assert_equal "1234", contacts.first.sales_tax_registration_number
      assert_equal true, contacts.first.uses_contact_invoice_sequence
      assert_equal 1000.0, contacts.first.account_balance
    end

    should "lookup a single contact" do
      contact = @costagent.contact(1)
      assert_equal 1, contact.id
      assert_equal 2, contact.projects.length
      assert_equal "Test Ltd", contact.organisation_name
      assert_equal "Test", contact.first_name
      assert_equal "Testerson", contact.last_name
      assert_equal "Test Address 1", contact.address1
      assert_equal "Test Address 2", contact.address2
      assert_equal "Test Address 3", contact.address3
      assert_equal "Test Town", contact.town
      assert_equal "Test Region", contact.region
      assert_equal "United Kingdom", contact.country
      assert_equal "Test Postcode", contact.postcode
      assert_equal "01234 567890", contact.phone_number
      assert_equal "test@test.com", contact.email
      assert_equal "test@test.com", contact.billing_email
      assert_equal true, contact.contact_name_on_invoices
      assert_equal "1234", contact.sales_tax_registration_number
      assert_equal true, contact.uses_contact_invoice_sequence
      assert_equal 1000.0, contact.account_balance    
    end
  end

  def setup_projects_test_response(filter = "active")
    xml =<<EOF
<projects>
  <project>
    <id>1</id>
    <contact-id>1</contact-id>
    <name>test project</name>
    <currency>GBP</currency>
    <normal-billing-rate>45</normal-billing-rate>
    <billing-period>hour</billing-period>
    <hours-per-day>8.0</hours-per-day>
  </project>
  <project>
    <id>2</id>
    <contact-id>1</contact-id>
    <name>test project 2</name>
    <currency>GBP</currency>
    <normal-billing-rate>400</normal-billing-rate>
    <billing-period>day</billing-period>
    <hours-per-day>8.0</hours-per-day>
  </project>
</projects>
EOF
    setup_test_response(xml, "projects", "view=#{filter}")
  end

  def setup_timeslips_test_response(parameters)
    xml =<<EOF
<timeslips>
  <timeslip>
    <id>1</id>
    <project-id>1</project-id>
    <task-id>1</task-id>
    <hours>10</hours>
    <updated-at>2010-05-09T14:25:57+01:00</updated-at>
    <dated-on>2010-05-09T14:25:57+01:00</dated-on>
    <comment>test comment</comment>
    <status>Locked</status>
  </timeslip>
  <timeslip>
    <id>2</id>
    <project-id>1</project-id>
    <task-id>1</task-id>
    <hours>8</hours>
    <updated-at>2010-05-09T23:45:01+01:00</updated-at>
    <dated-on>2010-05-09T23:45:01+01:00</dated-on>
    <comment>test comment</comment>
    <status>Locked</status>
  </timeslip>
</timeslips>
EOF
    setup_test_response(xml, "timeslips", parameters)
  end

  def setup_tasks_test_response(project_id)
    xml =<<EOF
<tasks>
  <task>
    <id>1</id>
    <project-id>1</project-id>
    <name>Development</name>
    <billing-period>hour</billing-period>
    <billing-rate>45.0</billing-rate>
    <is-billable>true</is-billable>
  </task>
  <task>
    <id>2</id>
    <project-id>1</project-id>
    <name>Design</name>
    <billing-period>hour</billing-period>
    <billing-rate>0.0</billing-rate>
    <is-billable>false</is-billable>
  </task>
</tasks>
EOF
    setup_test_response(xml, "projects/#{project_id}/tasks")
  end

  def setup_invoices_test_response
    xml =<<EOF
<invoices>
  <invoice>
    <id>1</id>
    <project-id>1</project-id>
    <description>test invoice</description>
    <reference>TEST001</reference>
    <net-value>100.0</net-value>
    <status>Sent</status>
    <dated-on>2010-10-09T07:16:00+01:00</dated-on>
    <due-on>2010-10-16T00:00:00+01:00</due-on>
    <invoice-items>
      <invoice-item>
        <id>1</id>
        <invoice-id>1</invoice-id>
        <project-id>1</project-id>
        <item-type>Hours</item-type>
        <description>test invoice item</description>
        <price>45.0</price>
        <quantity>12.0</quantity>
      </invoice-item>
    </invoice-items>
  </invoice>
</invoices>
EOF
    setup_test_response(xml, "invoices")
  end

  def setup_contacts_test_response
    xml =<<EOF
<contact>
  <id type="integer">1</id>
  <organisation-name>Test Ltd</organisation-name>
  <first-name>Test</first-name>
  <last-name>Testerson</last-name>
  <address1>Test Address 1</address1>
  <address2>Test Address 2</address2>
  <address3>Test Address 3</address3>
  <town>Test Town</town>
  <region>Test Region</region>
  <country>United Kingdom</country>
  <postcode>Test Postcode</postcode>
  <phone-number>01234 567890</phone-number>
  <email>test@test.com</email>
  <billing-email>test@test.com</billing-email>
  <contact-name-on-invoices type="boolean">true</contact-name-on-invoices>
  <sales-tax-registration-number>1234</sales-tax-registration-number>
  <uses-contact-invoice-sequence type="boolean">true</uses-contact-invoice-sequence>
  <account-balance>1000.00</account-balance>
</contact>
EOF
    setup_test_response(xml, "contacts")
  end

  def setup_test_response(xml, resource, parameters = nil, headers = {})
    @costagent = CostAgent.new("subdomain", "username", "password")
    rest = Struct.new(nil).new
    response = Struct.new(:body, :headers).new(xml, headers)
    RestClient::Resource.expects(:new).with("https://subdomain.freeagentcentral.com/#{resource}#{parameters.nil? ? "" : "?" + parameters}", "username", "password").returns(rest)
    rest.expects(:get).returns(response)
  end
end
