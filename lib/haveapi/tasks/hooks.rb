def document_hooks(rdoc, file = 'doc/Hooks.md')
  src = File.join(File.dirname(__FILE__), '..', '..', '..', 'doc', 'hooks.erb')

  rdoc.before_running_rdoc do
    File.write(
        file,
        ERB.new(File.read(src), 0).result(binding)
    )
  end
end
