require "rubygems"
require "test/unit"
require "shoulda"
require "mocha"
require File.join(File.dirname(__FILE__), "..", "lib", "costagent")

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
      assert_equal 1, projects.length
      assert_equal 1, projects.first.id
      assert_equal "test project", projects.first.name
      assert_equal "GBP", projects.first.currency
      assert_equal 45.0, projects.first.hourly_billing_rate
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
      setup_projects_test_response
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
      setup_projects_test_response
    end

    should "parse response for tasks" do
      tasks = @costagent.tasks(@costagent.projects.first.id)
      assert_equal 2, tasks.length
      assert_equal 1, tasks.first.id
      assert_equal 1, tasks.first.project.id
      assert_equal "Development", tasks.first.name
      assert_equal 2, tasks.last.id
      assert_equal 1, tasks.last.project.id
      assert_equal "Design", tasks.last.name
    end
  end

  context "request to query amount earnt" do
    setup do
      @start = DateTime.now - 1
      @end = DateTime.now + 1
      setup_timeslips_test_response("view=#{@start.strftime("%Y-%m-%d")}_#{@end.strftime("%Y-%m-%d")}")
      setup_projects_test_response
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

  def setup_projects_test_response
    xml =<<EOF
<projects>
  <project>
    <id>1</id>
    <name>test project</name>
    <currency>GBP</currency>
    <normal-billing-rate>45</normal-billing-rate>
  </project>
</projects>
EOF
    setup_test_response(xml, "projects")
  end

  def setup_timeslips_test_response(parameters)
    xml =<<EOF
<timeslips>
  <timeslip>
    <id>1</id>
    <project-id>1</project-id>
    <hours>10</hours>
    <updated-at>2010-05-09T14:25:57+01:00</updated-at>
  </timeslip>
  <timeslip>
    <id>2</id>
    <project-id>1</project-id>
    <hours>8</hours>
    <updated-at>2010-05-09T23:45:01+01:00</updated-at>
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

  def setup_test_response(xml, resource, parameters = nil)
    @costagent = CostAgent.new("subdomain", "username", "password")
    rest = Struct.new(nil).new
    response = Struct.new(:body).new(xml)
    RestClient::Resource.expects(:new).with("https://subdomain.freeagentcentral.com/#{resource}#{parameters.nil? ? "" : "?" + parameters}", "username", "password").returns(rest)
    rest.expects(:get).returns(response)
  end
end
