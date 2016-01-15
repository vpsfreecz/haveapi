require 'haveapi/tasks/hooks'

def render_doc_file(src, dst)
  src = File.join(File.dirname(__FILE__), '..', '..', '..', src)

  Proc.new do
    File.write(
        dst,
        ERB.new(File.read(src), 0).result(binding)
    )
  end
end
