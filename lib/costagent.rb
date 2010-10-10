require "rubygems"
require "date"
gem "rest-client"; require "rest_client"
gem "hpricot"; require "hpricot"
require "open-uri"

#  This exposes additional billable tracking functionality around the Freeagent API
class CostAgent
  Project = Struct.new(:id, :name, :currency, :hourly_billing_rate)
  Timeslip = Struct.new(:id, :project, :hours, :date, :cost)
  Task = Struct.new(:id, :name, :project)

  attr_accessor :subdomain, :username, :password
  
  def initialize(subdomain, username, password)
    self.subdomain = subdomain
    self.username = username
    self.password = password

    [:subdomain, :username, :password].each do |f|
      raise "No #{f} configured!" if self.send(f).nil? || self.send(f).empty?
    end
  end
    
  # Returns all projects
  def projects(filter = "active")
    @projects ||= {}
    @projects[filter] ||= (self.api("projects", {:view => filter})/"project").collect { |project| Project.new((project/"id").text.to_i, (project/"name").text, (project/"currency").text, (project/"normal-billing-rate").text.to_f) }
  end
    
  # This returns the specified project
  def project(id)
    self.projects("all").detect { |p| p.id == id }
  end

  # This returns all timeslips for the specified date range, with additional cost information
  def timeslips(start_date = DateTime.now, end_date = start_date)
    (self.api("timeslips", :view => "#{start_date.strftime("%Y-%m-%d")}_#{end_date.strftime("%Y-%m-%d")}")/"timeslip").collect do |timeslip|
      # Find the project and hours for this timeslip
      project = self.project((timeslip/"project-id").text.to_i)
      if project
        hours = (timeslip/"hours").text.to_f
        # Build the timeslip out using the timeslip data and the project it's tied to
        Timeslip.new((timeslip/"id").text.to_i,
                     project,
                     hours,
                     DateTime.parse((timeslip/"dated-on").text),
                     project.hourly_billing_rate * hours)
      else
        nil
      end
    end - [nil]
  end

  # This returns all tasks for the specified project_id
  def tasks(project_id)
    (self.api("projects/#{project_id}/tasks")/"task").collect do |task|
      # Find the project for this task
      project = self.project((task/"project-id").text.to_i)
      # Build the task out using the task data and the project it's tied to
      Task.new((task/"id").text.to_i,
                   (task/"name").text,
                   project)
    end
  end

  # This looks up the user ID using the CostAgent credentials
  def user_id
    self.client("verify").get.headers[:user_id]
  end

  # This returns the amount of hours worked
  def worked(start_date = DateTime.now, end_date = start_date)
    self.timeslips(start_date, end_date).collect do |timeslip|
      timeslip.hours
    end.inject(0) { |sum, i| sum += i }
  end
    
  # This returns the amount of GBP earnt in the specified timeframe
  def earnt(start_date = DateTime.now, end_date = start_date)
    self.timeslips(start_date, end_date).collect do |timeslip|
      if timeslip.project.currency == "GBP"
        timeslip.cost
      else
        timeslip.cost / CostAgent.usd_rate
      end
    end.inject(0) { |sum, i| sum += i }
  end
    
  # This calls the FA API for the specified resource
  def api(resource, parameters = {})
    res = self.client(resource, parameters).get
    raise "No response from #{url}!" if res.body.nil? && res.body.empty?
    Hpricot(res.body)
  end

  # This returns a client ready to query the FA API
  def client(resource, parameters = {})
    url = "https://#{self.subdomain}.freeagentcentral.com/#{resource}#{parameters.empty? ? "" : "?" + parameters.collect { |p| p.join("=") }.join("&")}"
    RestClient::Resource.new(url, self.username, self.password)
  end

  class << self
    # This returns the current USD rate from xe.com (or falls back on 1.6 if there is an error)
    def usd_rate
      @@rate ||= ((Hpricot(Kernel.open("http://www.xe.com"))/"a").detect { |a| a.attributes["id"] == "USDGBP31" }.children.first.to_s.to_f rescue 1.6)
    end
  end
end
