require 'haveapi/tasks/hooks'

def render_doc_file(src, dst)
  src = File.join(File.dirname(__FILE__), '..', '..', '..', src)

  proc do
    File.write(
      dst,
      ERB.new(File.read(src)).result(binding)
    )
  end
end
