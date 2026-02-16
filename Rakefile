require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Default task
task default: %i[spec rubocop]

# RSpec tests
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = '--format documentation --color'
end

# RuboCop linting
RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ['--display-cop-names']
end

# RuboCop auto-correct
RuboCop::RakeTask.new('rubocop:auto_correct') do |t|
  t.options = ['--auto-correct']
end

# Console for manual testing
desc 'Open an IRB session with Russula loaded'
task :console do
  require 'irb'
  require_relative 'lib/russula'
  ARGV.clear
  IRB.start
end

# Run examples
desc 'Run example scripts'
task :examples do
  Dir['examples/*.rb'].each do |example|
    puts "\nRunning #{example}..."
    puts '=' * 80
    system("ruby #{example}")
    puts '=' * 80
  end
end

# Clean up generated files
desc 'Clean up generated files'
task :clean do
  FileUtils.rm_rf('pkg')
  FileUtils.rm_rf('coverage')
  FileUtils.rm_rf('.yardoc')
  FileUtils.rm_rf('doc')
  FileUtils.rm_f('.rspec_status')
  puts 'Cleaned up generated files'
end

# Statistics
desc 'Show code statistics'
task :stats do
  require 'pathname'

  def count_lines(pattern)
    files = Dir[pattern]
    lines = files.sum { |f| File.readlines(f).count }
    [files.count, lines]
  end

  lib_files, lib_lines = count_lines('lib/**/*.rb')
  spec_files, spec_lines = count_lines('spec/**/*.rb')
  total_files = lib_files + spec_files
  total_lines = lib_lines + spec_lines

  puts "\nCode Statistics"
  puts '=' * 50
  puts "Library files: #{lib_files} (#{lib_lines} lines)"
  puts "Spec files: #{spec_files} (#{spec_lines} lines)"
  puts '-' * 50
  puts "Total: #{total_files} files (#{total_lines} lines)"
  puts "Test ratio: #{(spec_lines.to_f / lib_lines * 100).round(2)}%"
  puts '=' * 50
end
