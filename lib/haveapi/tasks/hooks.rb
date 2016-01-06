def document_hooks(file = 'doc/Hooks.md')
  src = File.join(File.dirname(__FILE__), '..', '..', '..', 'doc', 'hooks.erb')

  Proc.new do
    File.write(
        file,
        ERB.new(File.read(src), 0).result(binding)
    )
  end
end
