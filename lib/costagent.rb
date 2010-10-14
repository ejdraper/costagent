require "rubygems"
require "date"
gem "rest-client"; require "rest_client"
gem "hpricot"; require "hpricot"
require "open-uri"

#  This exposes additional billable tracking functionality around the Freeagent API
class CostAgent
  # This provides shared functionality for all of the wrapped FA data types
  class Base
    attr_accessor :data

    def initialize(data = {})
      @data = data
    end

    def method_missing(name, *args)
      key = name.to_s
      if key[key.length - 1] == "="
        @data[key[0...key.length - 1]] = args.first
      end
      @data[key] || @data[key.to_sym]
    end

    def id
      @data["id"] || @data[:id]
    end
  end

  # Our FA data types
  class Project < Base; end
  class Timeslip < Base; end
  class Task < Base; end
  class Invoice < Base; end
  class InvoiceItem < Base; end
  class User < Base; end

  # Our configuration for FA access
  attr_accessor :subdomain, :username, :password
  
  # Our cache provider, to help to limit the amount of requests and lookups to FA
  class << self
    attr_accessor :cache_provider
  end

  # This calls out to the external third party provider for caching
  def cache(resource, identifier, reload = false, &block)
    if CostAgent.cache_provider.nil?
      block.call
    else
      if (!reload && CostAgent.cache_provider.exists?(self.subdomain, resource, identifier))
        CostAgent.cache_provider.get(self.subdomain, resource, identifier)
      else
        CostAgent.cache_provider.set(self.subdomain, resource, identifier, block.call)
      end
    end
  end

  # Initialize and validate input data
  def initialize(subdomain, username, password)
    self.subdomain = subdomain
    self.username = username
    self.password = password

    [:subdomain, :username, :password].each do |f|
      raise "No #{f} configured!" if self.send(f).nil? || self.send(f).empty?
    end
  end
    
  # Returns all projects
  def projects(filter = "active", reload = false)
    self.cache(CostAgent::Project, filter, reload) do
      (self.api("projects", {:view => filter})/"project").collect do |project|
        billing_rate = (project/"normal-billing-rate").text.to_f
        hours_per_day = (project/"hours-per-day").text.to_f
        billing_period = (project/"billing-period").text
        hourly_rate = (billing_period == "hour" ? billing_rate : billing_rate / hours_per_day)
        daily_rate = (billing_period == "hour" ? billing_rate * hours_per_day : billing_rate)
        Project.new(
          :id => (project/"id").text.to_i,
          :name => (project/"name").text,
          :currency => (project/"currency").text,
          :hourly_billing_rate => hourly_rate,
          :daily_billing_rate => daily_rate,
          :hours_per_day => hours_per_day)
      end
    end
  end

  # This returns the specified project
  def project(id)
    self.projects("all").detect { |p| p.id == id }
  end

  # This returns all timeslips for the specified date range, with additional cost information
  def timeslips(start_date = DateTime.now, end_date = start_date, reload = false)
    self.cache(CostAgent::Timeslip, "#{start_date.strftime("%Y-%m-%d")}_#{end_date.strftime("%Y-%m-%d")}", reload) do
      timeslips = (self.api("timeslips", :view => "#{start_date.strftime("%Y-%m-%d")}_#{end_date.strftime("%Y-%m-%d")}")/"timeslip").collect do |timeslip|
        # Find the project and hours for this timeslip
        project = self.project((timeslip/"project-id").text.to_i)
        if project
          task = self.tasks(project.id).detect { |t| t.id == (timeslip/"task-id").text.to_i }
          hours = (timeslip/"hours").text.to_f
          cost = (task.nil? ? project : task).hourly_billing_rate * hours
          # Build the timeslip out using the timeslip data and the project it's tied to
          Timeslip.new(
            :id => (timeslip/"id").text.to_i,
            :project_id => project.id,
            :project => project,
            :task_id => task.id,
            :task => task,
            :hours => hours,
            :date => DateTime.parse((timeslip/"dated-on").text),
            :cost => cost,
            :comment => (timeslip/"comment").text,
            :status => (timeslip/"status").text)
        else
          nil
        end
      end - [nil]
    end
  end

  # This returns all tasks for the specified project_id
  def tasks(project_id, reload = false)
    self.cache(CostAgent::Task, project_id, reload) do
      (self.api("projects/#{project_id}/tasks")/"task").collect do |task|
        # Find the project for this task
        project = self.project((task/"project-id").text.to_i)
        # Calculate rates
        billing_rate = (task/"billing-rate").text.to_f
        billing_period = (task/"billing-period").text
        hourly_rate = (billing_period == "hour" ? billing_rate : billing_rate / project.hours_per_day)
        daily_rate = (billing_period == "hour" ? billing_rate * project.hours_per_day : billing_rate)
        # Build the task out using the task data and the project it's tied to
        Task.new(
          :id => (task/"id").text.to_i,
          :name => (task/"name").text,
          :project_id => project.id,
          :project => project,
          :hourly_billing_rate => hourly_rate,
          :daily_billing_rate => daily_rate,
          :billable => (task/"is-billable").text == "true")
      end
    end
  end

  # This returns all invoices
  def invoices(reload = false)
    self.cache(CostAgent::Invoice, :all, reload) do
      (self.api("invoices")/"invoice").collect do |invoice|
        items = (invoice/"invoice-item").collect do |item|
          price = (item/"price").first.inner_text.to_f
          quantity = (item/"quantity").first.inner_text.to_f
          cost = price * quantity
          project = self.project((item/"project-id").first.inner_text.to_i)
          InvoiceItem.new(
            :id => (item/"id").first.inner_text.to_i,
            :invoice_id => (item/"invoice-id").first.inner_text.to_i,
            :project_id => project.nil? ? nil : project.id,
            :project => project,
            :item_type => (item/"item-type").first.inner_text,
            :description => (item/"description").first.inner_text,
            :price => price,
            :quantity => quantity,
            :cost => cost)
        end
        project = self.project((invoice/"project-id").first.inner_text.to_i)
        Invoice.new(
          :id => (invoice/"id").first.inner_text.to_i,
          :project_id => project.nil? ? nil : project.id,
          :project => project,
          :description => (invoice/"description").first.inner_text,
          :reference => (invoice/"reference").text,
          :amount => (invoice/"net-value").text.to_f,
          :status => (invoice/"status").text,
          :date => DateTime.parse((invoice/"dated-on").text),
          :due => DateTime.parse((invoice/"due-on").text),
          :items => items)
      end
    end
  end

  # This returns the specific invoice by ID
  def invoice(id)
    self.invoices.detect { |i| i.id == id }
  end

  # This contains the logged in user information for the configured credentials
  def user(reload = false)
    self.cache(CostAgent::User, self.username, reload) do
      data = self.client("verify").get.headers
      [User.new(
        :id => data[:user_id],
        :permissions => data[:user_permission_level],
        :company_type => data[:company_type])]
    end.first
  end

  # This looks up the user ID using the CostAgent credentials
  def user_id
    self.user.id
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
