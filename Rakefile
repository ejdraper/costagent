require "rubygems"
require "rake/gempackagetask"
require "rake/rdoctask"

require "rake/testtask"
Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
end
task :default => ["test"]

spec = Gem::Specification.new do |s|

  s.name              = "costagent"
  s.version           = "0.2.1"
  s.summary           = "costagent is a Ruby gem that provides lightweight access to the projects/timeslips part of the FreeAgent API, with a view to tracking billable hours and figures."
  s.author            = "Elliott Draper"
  s.email             = "el@ejdraper.com"
  s.homepage          = "http://github.com/ejdraper/costagent"

  s.has_rdoc          = true
  s.extra_rdoc_files  = %w(README.rdoc)
  s.rdoc_options      = %w(--main README.rdoc)

  # Add any extra files to include in the gem
  s.files             = %w(README.rdoc) + Dir.glob("{test,lib/**/*}")
  s.require_paths     = ["lib"]

  # If you want to depend on other gems, add them here, along with any
  # relevant versions
  s.add_dependency("rest-client", "1.5.0")
  s.add_dependency("hpricot", "0.8.2")

  # If your tests use any gems, include them here
  s.add_development_dependency("shoulda")
  s.add_development_dependency("mocha")
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

desc "Build the gemspec file #{spec.name}.gemspec"
task :gemspec do
  file = File.dirname(__FILE__) + "/#{spec.name}.gemspec"
  File.open(file, "w") {|f| f << spec.to_ruby }
end

task :package => :gemspec

# Generate documentation
Rake::RDocTask.new do |rd|
  rd.main = "README.rdoc"
  rd.rdoc_files.include("README.rdoc", "lib/**/*.rb")
  rd.rdoc_dir = "rdoc"
end

desc 'Clear out RDoc and generated packages'
task :clean => [:clobber_rdoc, :clobber_package] do
  rm "#{spec.name}.gemspec"
end
