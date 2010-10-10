require "rubygems"
require "test/unit"
require "shoulda"
require "mocha"
require File.join(File.expand_path(File.dirname(__FILE__)), "..", "lib", "costagent")

class CostAgentTest < Test::Unit::TestCase
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
      setup_projects_test_response("all")
    end
    
    should "parse response for projects" do
      projects = @costagent.projects("all")
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
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
    end

    should "parse response for timeslips" do
      timeslips = @costagent.timeslips(@start, @end)
      assert_equal 2, timeslips.length
      assert_equal 1, timeslips.first.id
      assert_equal 1, timeslips.first.project.id
      assert_equal 10.0, timeslips.first.hours
      assert_equal 450.0, timeslips.first.cost
      assert_equal 2, timeslips.last.id
      assert_equal 1, timeslips.last.project.id
      assert_equal 8.0, timeslips.last.hours
      assert_equal 360.0, timeslips.last.cost
    end
  end

  context "request to query tasks for a given project" do
    setup do
      setup_tasks_test_response(1)
      setup_projects_test_response("all")
    end

    should "parse response for tasks" do
      tasks = @costagent.tasks(@costagent.projects("all").first.id)
      assert_equal 2, tasks.length
      assert_equal 1, tasks.first.id
      assert_equal 1, tasks.first.project.id
      assert_equal "Development", tasks.first.name
      assert_equal 2, tasks.last.id
      assert_equal 1, tasks.last.project.id
      assert_equal "Design", tasks.last.name
    end
  end

  context "request to query time worked" do
    setup do
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
    end

    should "return the right time for the timeslips" do
      assert_equal 18.0, @costagent.worked(@start, @end)
    end
  end
  
  context "request to query amount earnt" do
    setup do
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response("all")
    end

    should "return the right amount for the timeslips" do
      assert_equal 810.0, @costagent.earnt(@start, @end)
    end
  end

  context "request to query USD exchange rate" do
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

  context "request to query user_id" do
    setup do
      setup_test_response("", "verify", nil, {:user_id => "12345"})
    end
    
    should "make a call to the FA API to return the user_id" do
      assert_equal "12345", @costagent.user_id
    end
  end

  context "request to query all invoices" do
    setup do
      setup_invoices_test_response
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

  def setup_projects_test_response(filter = "active")
    xml =<<EOF
<projects>
  <project>
    <id>1</id>
    <name>test project</name>
    <currency>GBP</currency>
    <normal-billing-rate>45</normal-billing-rate>
    <billing-period>hour</billing-period>
    <hours-per-day>8.0</hours-per-day>
  </project>
  <project>
    <id>2</id>
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
    <hours>10</hours>
    <updated-at>2010-05-09T14:25:57+01:00</updated-at>
    <dated-on>2010-05-09T14:25:57+01:00</dated-on>
  </timeslip>
  <timeslip>
    <id>2</id>
    <project-id>1</project-id>
    <hours>8</hours>
    <updated-at>2010-05-09T23:45:01+01:00</updated-at>
    <dated-on>2010-05-09T23:45:01+01:00</dated-on>
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
  </task>
  <task>
    <id>2</id>
    <project-id>1</project-id>
    <name>Design</name>
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

  def setup_test_response(xml, resource, parameters = nil, headers = {})
    @costagent = CostAgent.new("subdomain", "username", "password")
    rest = Struct.new(nil).new
    response = Struct.new(:body, :headers).new(xml, headers)
    RestClient::Resource.expects(:new).with("https://subdomain.freeagentcentral.com/#{resource}#{parameters.nil? ? "" : "?" + parameters}", "username", "password").returns(rest)
    rest.expects(:get).returns(response)
  end
end
