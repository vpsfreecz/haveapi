require 'haveapi/client_examples/python_client'

module HaveAPI::ClientExamples
  class PythonAsyncClient < PythonClient
    label 'Python (async)'
    id 'python-async'
    code :python
    order 15

    def asynchronous?
      true
    end
  end
end
