# Saved SDK schema fixture. Generated Go source is always produced by Generator.
module GoDocumentationFixture
  def self.io(parameters, layout: 'hash', namespace: 'widget')
    { layout:, namespace:, parameters: }
  end

  def self.action(path: '/mounted/v7/widgets', method: 'POST', input: nil, output: nil, aliases: [], blocking: false, meta: {})
    { path:, method:, input:, output:, aliases:, blocking:, meta: }
  end

  def self.token
    output = io({ complete: { type: 'Boolean' }, token: { type: 'String' }, next_action: { type: 'String' } }, namespace: 'token')
    {
      http_header: 'X-Token', query_parameter: 'token',
      resources: {
        token: {
          resources: {},
          actions: {
            request: action(path: '/mounted/v7/tokens', input: io({ user: { type: 'String' }, password: { type: 'String' },
                                                                    lifetime: { type: 'String' }, interval: { type: 'Integer' } }), output:),
            challenge: action(path: '/mounted/v7/tokens/challenge', input: io({ token: { type: 'String' }, code: { type: 'String' } }), output:),
            revoke: action(path: '/mounted/v7/tokens/revoke')
          }
        }
      }
    }
  end

  def self.description
    state = {
      resources: {},
      actions: {
        show: action(path: '/mounted/v7/action_states/{action_state_id}', method: 'GET',
                     output: io({ id: { type: 'Integer' } }, namespace: 'action_state')),
        poll: action(path: '/mounted/v7/action_states/{action_state_id}/poll', method: 'GET',
                     input: io({ timeout: { type: 'Float' }, update_in: { type: 'Float' },
                                 status: { type: 'String' }, current: { type: 'Integer' }, total: { type: 'Integer' } }),
                     output: io({ finished: { type: 'Boolean' }, status: { type: 'String' },
                                  current: { type: 'Integer' }, total: { type: 'Integer' } }, namespace: 'action_state')),
        cancel: action(path: '/mounted/v7/action_states/{action_state_id}/cancel', method: 'POST')
      }
    }
    run = action(
      path: '/mounted/v7/clients/{client_id}/children/{child_id}', aliases: ['perform'],
      input: io({ name: { type: 'String', nullable: true }, enabled: { type: 'Boolean' },
                  count: { type: 'Integer' }, unused: { type: 'String' } }),
      output: io({ id: { type: 'Integer' }, name: { type: 'String', nullable: true } }),
      meta: { global: { input: io({ includes: { type: 'Custom' } }, namespace: false) } }
    )
    {
      authentication: { basic: {}, token: token, oauth2: { http_header: 'X-OAuth', revoke_url: '/revoke' } },
      meta: { namespace: '_meta' },
      resources: {
        action_state: state,
        owner: { resources: {}, actions: {
          show: action(path: '/mounted/v7/owners/{owner_id}', method: 'GET',
                       output: io({ id: { type: 'Integer' }, label: { type: 'String' } }, namespace: 'owner'))
        } },
        client: { resources: { child: { resources: {}, actions: { client: run } } }, actions: {} },
        authentication: { resources: {}, actions: {} },
        hidden: { resources: {}, actions: { secret: action } }
      }
    }
  end

  def self.sample
    { path_params: [42, 'a/b'], request: { name: nil, enabled: false, count: 0 },
      response: { id: 1 }, status: true }
  end
end
