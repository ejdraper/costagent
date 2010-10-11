require "rubygems"
require "date"
gem "rest-client"; require "rest_client"
gem "hpricot"; require "hpricot"
require "open-uri"

#  This exposes additional billable tracking functionality around the Freeagent API
class CostAgent
  Project = Struct.new(:id, :name, :currency, :hourly_billing_rate, :daily_billing_rate, :hours_per_day)
  Timeslip = Struct.new(:id, :project, :task, :hours, :date, :cost, :comment, :status)
  Task = Struct.new(:id, :name, :project, :hourly_billing_rate, :daily_billing_rate, :billable)
  Invoice = Struct.new(:id, :project_id, :description, :reference, :amount, :status, :date, :due, :items)
  InvoiceItem = Struct.new(:id, :invoice_id, :project_id, :item_type, :description, :price, :quantity, :cost)

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
    @projects[filter] ||= (self.api("projects", {:view => filter})/"project").collect do |project|
      billing_rate = (project/"normal-billing-rate").text.to_f
      hours_per_day = (project/"hours-per-day").text.to_f
      billing_period = (project/"billing-period").text
      hourly_rate = (billing_period == "hour" ? billing_rate : billing_rate / hours_per_day)
      daily_rate = (billing_period == "hour" ? billing_rate * hours_per_day : billing_rate)
      Project.new((project/"id").text.to_i,
                  (project/"name").text,
                  (project/"currency").text,
                  hourly_rate,
                  daily_rate,
                  hours_per_day)
    end
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
        task = self.tasks(project.id).detect { |t| t.id == (timeslip/"task-id").text.to_i }
        hours = (timeslip/"hours").text.to_f
        cost = (task.nil? ? project : task).hourly_billing_rate * hours
        # Build the timeslip out using the timeslip data and the project it's tied to
        Timeslip.new((timeslip/"id").text.to_i,
                     project,
                     task,
                     hours,
                     DateTime.parse((timeslip/"dated-on").text),
                     cost,
                     (timeslip/"comment").text,
                     (timeslip/"status").text)
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
      # Calculate rates
      billing_rate = (task/"billing-rate").text.to_f
      billing_period = (task/"billing-period").text
      hourly_rate = (billing_period == "hour" ? billing_rate : billing_rate / project.hours_per_day)
      daily_rate = (billing_period == "hour" ? billing_rate * project.hours_per_day : billing_rate)
      # Build the task out using the task data and the project it's tied to
      Task.new((task/"id").text.to_i,
                   (task/"name").text,
                   project,
                   hourly_rate,
                   daily_rate,
                   (task/"is-billable").text == "true")
    end
  end

  # This returns all invoices
  def invoices
    @invoices ||= (self.api("invoices")/"invoice").collect do |invoice|
      items = (invoice/"invoice-item").collect do |item|
        price = (item/"price").first.inner_text.to_f
        quantity = (item/"quantity").first.inner_text.to_f
        cost = price * quantity
        InvoiceItem.new(
          (item/"id").first.inner_text.to_i,
          (item/"invoice-id").first.inner_text.to_i,
          (item/"project-id").first.inner_text.to_i,
          (item/"item-type").first.inner_text,
          (item/"description").first.inner_text,
          price,
          quantity,
          cost)
      end
      Invoice.new(
        (invoice/"id").first.inner_text.to_i,
        (invoice/"project-id").first.inner_text.to_i,
        (invoice/"description").first.inner_text,
        (invoice/"reference").text,
        (invoice/"net-value").text.to_f,
        (invoice/"status").text,
        DateTime.parse((invoice/"dated-on").text),
        DateTime.parse((invoice/"due-on").text),
        items)
    end
    @invoices
  end

  # This returns the specific invoice by ID
  def invoice(id)
    self.invoices.detect { |i| i.id == id }
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
