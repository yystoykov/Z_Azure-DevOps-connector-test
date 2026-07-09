{
  title: 'Azure DevOps Reset Test Connector',

  connection: {
    fields: [
      { name: 'auth_type', control_type: 'select',
        options: [['Type A', 'type_a'], ['Type B (missing param)', 'type_b']],
        extends_schema: true,
        optional: false }
    ],

    authorization: {
      type: 'multi',
      selected: lambda do |connection|
        connection['auth_type'] || 'type_a'
      end,
      options: {
        type_a: {
          type: 'custom_auth',
          fields: [{ name: 'api_key', label: 'API Key', optional: false }],
          apply: lambda do |connection|
            headers('X-API-Key': connection['api_key']).
              params('version': '1.0')
          end
        },
        type_b: {
          type: 'custom_auth',
          fields: [{ name: 'api_key', label: 'API Key', optional: false }],
          apply: lambda do |connection|
            headers('X-API-Key': connection['api_key']).
              params('version': '2.0')   # should not cause restart
            # intentionally missing .params('version': '1.0') — mirrors the ADO bug
          end
        }
      }
    },

    base_uri: lambda do |_connection|
      'https://webhook.site'
    end
  },

  test: lambda do |_connection|
    { status: 'ok', version: 'v26' }
    #error("VERSION_CHECK: v25")
  end,

  triggers: {
    new_event: {
      title: 'Poll for version check',

    poll: lambda do |_connection, _input, closure|
      response = get('https://httpbin.org/get').
        after_error_response(/.*/) do |_code, _body, _headers, _message|
          { 'args' => {} }
        end

      n = closure.is_a?(Hash) ? closure['n'].to_s.to_i + 1 : 1
      {
        events: [{
          id: "v26-#{n}",
          connector_version: 'v26',
          version_param: response['args']['version'] || 'not sent'
        }],
        next_poll: 30,
        can_poll_more: false,
        next_closure: { 'n' => n.to_s }
      }
    end,

    dedup: lambda do |event|
      event['id']
    end,

    output_fields: lambda do |_|
      [
        { name: 'id' },
        { name: 'connector_version' },
        { name: 'version_param' }
      ]
    end
    }
  }
}