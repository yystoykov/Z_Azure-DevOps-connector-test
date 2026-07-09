{
  title: 'Azure DevOps',

  connection: {
    fields: [
      { name: 'auth_type', control_type: 'select',
        label: 'OAuth 2.0 grant type',
        optional: false, default: 'token',
        extends_schema: true,
        options: [
          ['Authorization code', 'oauth2'],
          ['Personal access token', 'token'],
          ['Service Principal', 'service_principal']
        ] },
      { name: 'organization', optional: false },
      { name: 'api_version',
        label: 'API version',
        optional: false,
        hint: 'E.g. <b>7.0, 7.1-preview.7, 6.0</b><br>' \
              "Click <a href='https://docs.microsoft.com/en-us/azure/devops/" \
              "integrate/concepts/rest-api-versioning?view=azure-devops' " \
              "target='_blank'>here</a> to learn more about API versioning." }
    ],

    authorization: {
      type: 'multi',

      selected: lambda do |connection|
        connection['auth_type'] || 'token'
      end,

      options: {
        oauth2: {
          type: 'oauth2',

          fields: [
            { name: 'client_id', optional: false,
              hint: "Visit Azure DevOps <a href='https://learn.microsoft.com/en-us/" \
                    "azure/devops/integrate/get-started/authentication/oauth?view=azure-devops' " \
                    "target='_blank'>documentation</a> to register client app." },
            { name: 'client_secret', control_type: 'password', optional: false,
              hint: "Visit Azure DevOps <a href='https://learn.microsoft.com/en-us/" \
                    "azure/devops/integrate/get-started/authentication/oauth?view=azure-devops' " \
                    "target='_blank'>documentation</a> to register client app." },
            { name: 'scopes', optional: false,
              hint: 'Provide the scopes from the client app. E.g. vso.code_full vso.work_full' }
          ],

          authorization_url: lambda do |connection|
            'https://app.vssps.visualstudio.com/oauth2/authorize?' \
              "client_id=#{connection['client_id']}&response_type=Assertion&" \
              'redirect_uri=https%3A%2F%2Fwww.workato.com%2Foauth%2Fcallback&' \
              "scope=#{connection['scopes']&.encode_url}"
          end,

          acquire: lambda do |connection, auth_code, _redirect_url|
            post('https://app.vssps.visualstudio.com/oauth2/token').
              payload(
                client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
                client_assertion: connection['client_secret'],
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion: auth_code,
                redirect_uri: 'https://www.workato.com/oauth/callback'
              ).request_format_www_form_urlencoded
          end,

          refresh_on: [401, 403, /Azure DevOps Services | Sign In/],

          detect_on: [/Azure DevOps Services | Sign In/],

          refresh: lambda do |connection, refresh_token|
            post('https://app.vssps.visualstudio.com/oauth2/token').
              payload(
                client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
                client_assertion: connection['client_secret'],
                grant_type: 'refresh_token',
                assertion: refresh_token,
                redirect_uri: 'https://www.workato.com/oauth/callback'
              ).request_format_www_form_urlencoded
          end,

          apply: lambda do |connection, access_token|
            headers(Authorization: "Bearer #{access_token}").
              params('api-version': connection['api_version'])
          end
        },
        token: {
          type: 'api_key',

          fields: [
            { name: 'username', optional: false,
              hint: 'Provide the username to use with Personal access token.' },
            { name: 'api_key', label: 'Personal access token',
              control_type: 'password', optional: false,
              hint: "Visit Azure DevOps <a href='https://docs.microsoft.com/en-us/" \
                    'azure/devops/organizations/accounts/use-personal-access-tokens-to-' \
                    "authenticate?view=azure-devops&tabs=Windows#create-a-pat' " \
                    "target='_blank'>documentation</a> to create a Personal access token." }
          ],

          apply: lambda do |connection|
            credentials = "#{connection['username']}:#{connection['api_key']}".encode_base64
            headers(Authorization: "Basic #{credentials}").
              params('api-version': connection['api_version'])
          end
        },
        service_principal: {
          fields: [
            {
              name: 'client_id',
              optional: false,
              hint: "Click <a href= 'https://learn.microsoft.com/en-us/azure/devops/integrate/" \
                    'get-started/authentication/' \
                    'service-principal-managed-' \
                    "identity?view=azure-devops' " \
                    "target='_blank'>here</a> to learn " \
                    'how to generate the Client ID and Client secret ' \
                    'for your Service Principal.'
            },
            {
              name: 'client_secret',
              control_type: 'password',
              hint: "Click <a href= 'https://learn.microsoft.com/en-us/" \
                    'azure/devops/integrate/' \
                    'get-started/authentication/' \
                    'service-principal-managed-' \
                    "identity?view=azure-devops' " \
                    "target='_blank'>here</a> to learn " \
                    'how to generate the Client ID and Client secret ' \
                    'for your Service Principal.'
            },
            {
              name: 'tenant_id',
              label: 'Tenant ID',
              optional: false,
              hint: 'Tenant ID is generated during App registration process ' \
                    'for Client ID and Client secret. Use the tenant ID from Oauth client app. ' \
                    'This can be in GUID or friendly name format.<br>' \
                    'e.g. company.onmicrosoft.com or xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
            }
          ],

          type: 'custom_auth',

          acquire: lambda do |connection|
            post("https://login.microsoftonline.com/#{connection['tenant_id']}/oauth2/v2.0/token").
              payload(grant_type: 'client_credentials',
                      client_id: connection['client_id'],
                      client_secret: connection['client_secret'],
                      scope: '499b84ac-1321-427f-aa17-267ca6975798/.default').
              request_format_www_form_urlencoded.
              after_error_response(/.*/) do |_code, body, _header, message|
                error("#{message}: #{body}")
              end
          end,

          refresh_on: [401, 403, /Azure DevOps Services | Sign In/],

          detect_on: [/Azure DevOps Services | Sign In/],

          apply: lambda do |connection|
            headers(Authorization: "Bearer #{connection['access_token']}").
              params('api-version': connection['api_version'])
          end
        }
      }
    },

    base_uri: lambda do |connection|
      "https://dev.azure.com/#{connection['organization']}/"
    end
  },

  test: lambda do |_connection|
    get('_apis/projects?$top=1')
  end,

  methods: {
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky', field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__[0-9a-fA-F]+__/) do |string|
            string.gsub('__', '').decode_hex.as_utf8
          end
          value = call('format_payload', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      end
    end,
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          value = call('format_response', value) if value.is_a?(Array) || value.is_a?(Hash)
          hash[key] = value
        end
      else
        response
      end
    end,

    get_url: lambda do |input|
      case input['object']
      when 'work_item'
        "#{input.delete('project').encode_url}/_apis/wit/workitems"
      when 'build'
        "#{input.delete('project').encode_url}/_apis/build/builds"
      when 'build_log'
        "#{input.delete('project').encode_url}/_apis/build/builds/" \
        "#{input.delete('build_id')}/logs"
      when 'run'
        "#{input.delete('project').encode_url}/_apis/pipelines/" \
        "#{input.delete('pipeline_id')}/runs"
      when 'project'
        '_apis/projects'
      when 'board'
        "#{input.delete('project').encode_url}/#{input.delete('team')}/_apis/work/boards"
      when 'board_column'
        "#{input.delete('project').encode_url}/_apis/work/boardcolumns"
      else
        input['object'].pluralize
      end
    end,

    pick_list_with_children: lambda do |input|
      path = []
      root_path = "#{input['root_path']}\\#{input['area']['name']}"
      path << [root_path.gsub(/^./, '')]

      if input['area']['children'].present?
        input['area']['children'].map do |array_value|
          path << call('pick_list_with_children',
                       'area' => array_value, 'root_path' => root_path)
        end
      end
      path.flatten
    end,

    project_search_input: lambda do
      [
        { name: 'stateFilter',
          hint: 'Filter on team projects in a specific team project state (default: WellFormed)',
          sticky: true },
        { name: '$skip',
          label: 'Offset',
          hint: 'Display the results based on the page number.',
          sticky: true },
        { name: '$top',
          label: 'Limit',
          sticky: true,
          hint: 'The maximum number of projects to return.' },
        { name: '%continuationToken',
          label: 'Continuation token',
          sticky: true,
          hint: 'Can be used to return the next set of projects.' },
        { name: 'getDefaultTeamImageUrl',
          type: 'boolean',
          control_type: 'checkbox',
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'getDefaultTeamImageUrl',
            label: 'Get default team image URL',
            type: 'boolean',
            control_type: 'text',
            convert_input: 'boolean_conversion',
            sticky: true,
            optional: true,
            hint: 'Valid values are: true or false.'
          } },
        { name: 'includeCapabilities',
          type: 'boolean',
          control_type: 'checkbox',
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'includeCapabilities',
            label: 'Include capabilities',
            type: 'boolean',
            control_type: 'text',
            convert_input: 'boolean_conversion',
            sticky: true,
            optional: true,
            hint: 'Valid values are: true or false.'
          } },
        { name: 'includeHistory',
          type: 'boolean',
          control_type: 'checkbox',
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'includeHistory',
            label: 'Include history',
            type: 'boolean',
            control_type: 'text',
            convert_input: 'boolean_conversion',
            sticky: true,
            optional: true,
            hint: 'Valid values are: true or false.'
          } }
      ]
    end,

    board_search_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          extends_schema: true,
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            extends_schema: true, change_on_blur: true,
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: 'team',
          label: 'Team ID or name',
          optional: false }
      ]
    end,

    board_column_search_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          extends_schema: true,
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            extends_schema: true, change_on_blur: true,
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } }
      ]
    end,

    work_item_search_input: lambda do |input|
      config_schema = [
        { name: 'project', optional: false,
          control_type: 'select',
          extends_schema: true,
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            extends_schema: true, change_on_blur: true,
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } }
      ]

      toggle_schema = [
        { name: 'ids', label: 'Work items IDs',
          control_type: 'multiselect',
          pick_list: 'work_items',
          pick_list_params: { project: 'project' },
          delimiter: ',',
          optional: false,
          hint: 'Please select the work items to return via their ID. ' \
                'Maximum of 200 work items allowed.',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'ids', label: 'Work item IDs',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'The comma-separated list of requested work item IDs to ' \
                  'return. Maximum 200 IDs allowed.'
          } },
        { name: 'asOf', type: 'date_time', sticky: true,
          hint: 'Return work items as of specific datetime.' },
        { name: '$expand', label: 'Expand', sticky: true,
          control_type: 'select',
          default: 'All',
          hint: 'Select the additional fields to return in the output.',
          pick_list: [
            %w[None None],
            %w[Relations Relations],
            %w[Fields Fields],
            %w[Links Links],
            %w[All All]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: '$expand', label: 'Expand',
            optional: true, sticky: true,
            type: 'string', control_type: 'text',
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are None, Relations, Fields, Links, All'
          } },
        { name: 'errorPolicy', sticky: true,
          control_type: 'select',
          hint: 'Select the additional fields to return in the output.',
          pick_list: [
            %w[Fail Fail],
            %w[Omit Omit]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'errorPolicy', label: 'Error policy',
            optional: true, sticky: true,
            type: 'string', control_type: 'text',
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are Fail, Omit'
          } },
        { name: 'fields', sticky: true,
          hint: 'Provide comma-separated fields to return in the output.' },
        { name: 'custom_fields',
          label: 'Work item fields',
          sticky: true,
          extends_schema: true,
          schema_neutral: true,
          hint: 'Provide a sample JSON to include work item custom fields.',
          control_type: 'schema-designer',
          sample_data_type: 'json_input' }
      ]

      has_datapill = input['project']&.include?("{_('data.") ||
                     input['project']&.include?('pill_type')

      if has_datapill
        toggle_schema = toggle_schema.ignored('ids').
                        push({
                               name: 'ids',
                               label: 'Work item IDs',
                               hint: 'The comma-separated list of requested work item IDs ' \
                                     'to return. Maximum 200 IDs allowed.',
                               optional: false
                             })
      end

      config_schema.concat(toggle_schema)
    end,

    work_item_get_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          extends_schema: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            extends_schema: true,
            hint: 'Enter project name'
          } },
        { name: 'id', label: 'Work item ID', optional: false },
        { name: 'asOf', type: 'date_time', sticky: true,
          hint: 'Return work items as of specific datetime.' },
        { name: '$expand', label: 'Expand', sticky: true,
          control_type: 'select',
          default: 'All',
          hint: 'Select the additional fields to return in the output.',
          pick_list: [
            %w[None None],
            %w[Relations Relations],
            %w[Fields Fields],
            %w[Links Links],
            %w[All All]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: '$expand', label: 'Expand',
            optional: true, sticky: true,
            type: 'string', control_type: 'text',
            toggle_hint: 'Use custom value',
            hint: 'Allowed values are None, Relations, Fields, Links, All'
          } },
        { name: 'fields', sticky: true,
          hint: 'Provide comma-separated fields to return in the output.' },
        { name: 'custom_fields',
          label: 'Work item fields',
          sticky: true,
          extends_schema: true,
          schema_neutral: true,
          hint: 'Provide a sample JSON to include work item custom fields.',
          control_type: 'schema-designer',
          sample_data_type: 'json_input' }
      ]
    end,

    generate_work_item_input: lambda do |input, action|
      next [] if input['project'].blank? || input['project_has_datapill'] ||
                 input['type'].blank? || input['work_item_type_has_datapill']

      all_fields = get("#{input['project'].encode_url}/_apis/wit/fields")&.
                   after_error_response(/.*/) do |_code, _body, _headers, _message|
                     {}
                   end&.[]('value') || []
      read_only_fields = all_fields&.
                         select { |field| field['readOnly'] == true }&.pluck('referenceName')

      work_item_fields = if input['work_item_type_has_datapill'] == true
                           []
                         else
                           type = if input['type'].include?('~')
                                    input['type'].split('~').last
                                  else
                                    input['type']
                                  end

                           get("#{input['project'].encode_url}/_apis/wit" \
                               "/workitemtypes/#{type}/fields?$expand=all")&.
                             after_error_response(/.*/) do |_code, _body, _headers, _message|
                               {}
                             end&.[]('value') || []
                         end
      work_item_fields&.select do |field|
        read_only_fields.
          push('System.AreaPath', 'System.IterationPath', 'System.AssignedTo',
               'System.WorkItemType',
               'System.CreatedDate', 'System.CreatedBy', 'System.ChangedDate', 'System.ChangedBy',
               'Microsoft.VSTS.Common.StateChangeDate', 'Microsoft.VSTS.Common.ActivatedDate',
               'Microsoft.VSTS.Common.ActivatedBy', 'Microsoft.VSTS.Common.ClosedDate',
               'Microsoft.VSTS.Common.ClosedBy').
          exclude?(field['referenceName'])
      end&.map do |field|
        optional = if action == 'update'
                     true
                   elsif action == 'create'
                     %w[System.IterationId System.AreaId].include?(field['referenceName']) ||
                       field['alwaysRequired'].is_not_true?
                   end
        type = all_fields&.select do |item|
          item['referenceName'] == field['referenceName']
        end&.dig(0, 'type') || 'string'
        case type
        when 'string'
          if field['allowedValues'].present?
            pick_list = field['allowedValues'].map { |option| [option, option] }
            {
              name: field['referenceName'],
              control_type: 'select',
              pick_list: pick_list,
              sticky: true,
              optional: optional,
              label: field['referenceName'].split('.').last.labelize,
              hint: field['helpText'],
              toggle_hint: 'Select from list',
              toggle_field: {
                toggle_hint: 'Enter custom value',
                name: field['referenceName'].gsub('.', '__2e__'),
                type: 'string',
                control_type: 'text',
                optional: optional,
                label: field['referenceName'].split('.').last.labelize,
                hint: 'Enter custom value.'
              }
            }
          else
            {
              name: field['referenceName'],
              type: 'string',
              control_type: 'text',
              sticky: true,
              optional: optional,
              label: field['referenceName'].split('.').last.labelize,
              hint: field['helpText']
            }
          end
        when 'boolean'
          {
            name: field['referenceName'],
            type: 'boolean',
            control_type: 'checkbox',
            render_input: 'boolean_conversion',
            parse_output: 'boolean_conversion',
            sticky: true,
            optional: optional,
            label: field['referenceName'].split('.').last.labelize,
            hint: field['helpText'],
            toggle_hint: 'Select from list',
            toggle_field: {
              toggle_hint: 'Enter custom value',
              name: field['referenceName'].gsub('.', '__2e__'),
              type: 'boolean',
              control_type: 'text',
              render_input: 'boolean_conversion',
              parse_output: 'boolean_conversion',
              label: field['referenceName'].split('.').last.labelize,
              optional: optional,
              hint: 'Valid values are: true or false.'
            }
          }
        when 'dateTime'
          {
            name: field['referenceName'],
            type: 'date_time',
            control_type: 'date_time',
            sticky: true,
            optional: optional,
            label: field['referenceName'].split('.').last.labelize,
            hint: field['helpText']
          }
        when 'double'
          {
            name: field['referenceName'],
            type: 'number',
            control_type: 'number',
            sticky: true,
            optional: optional,
            render_input: 'float_conversion',
            parse_output: 'float_conversion',
            label: field['referenceName'].split('.').last.labelize,
            hint: field['helpText']
          }
        when 'integer'
          if field['allowedValues'].present?
            pick_list = field['allowedValues'].map { |option| [option, option] }
            {
              name: field['referenceName'],
              control_type: 'select',
              pick_list: pick_list,
              sticky: true,
              optional: optional,
              label: field['referenceName'].split('.').last.labelize,
              hint: field['helpText'],
              toggle_hint: 'Select from list',
              toggle_field: {
                toggle_hint: 'Enter custom value',
                name: field['referenceName'].gsub('.', '__2e__'),
                type: 'integer',
                control_type: 'integer',
                optional: optional,
                label: field['referenceName'].split('.').last.labelize,
                hint: 'Enter custom value.'
              }
            }
          else
            {
              name: field['referenceName'],
              type: 'integer',
              control_type: 'integer',
              sticky: true,
              optional: optional,
              render_input: 'integer_conversion',
              parse_output: 'integer_conversion',
              label: field['referenceName'].split('.').last.labelize,
              hint: field['helpText']
            }
          end
        else
          {
            name: field['referenceName'],
            type: 'string',
            control_type: 'text',
            sticky: true,
            optional: optional,
            label: field['referenceName'].split('.').last.labelize,
            hint: field['helpText']
          }
        end
      end&.compact
    end,

    generate_work_item_output: lambda do |input|
      next [] if input['project'].blank? || input['project'].include?("{_('data.")

      has_datapill = input['has_datapill']
      work_item_fields = if input['type'].present? && has_datapill == false
                           get("#{input['project'].encode_url}/_apis/wit" \
                               "/workitemtypes/#{input['type'].split('~').last}/fields?$expand=all")
                         else
                           get("#{input['project'].encode_url}/_apis/wit/fields")
                         end&.after_error_response(/.*/) do |_code, _body, _headers, _message|
                           {}
                         end&.[]('value') || []
      work_item_fields&.select do |field|
        %w[System.Id System.State System.AssignedTo Microsoft.VSTS.Common.ActivatedBy
           Microsoft.VSTS.Common.ClosedBy System.CreatedBy
           System.ChangedBy System.AuthorizedAs].exclude?(field['referenceName'])
      end&.map do |field|
        case field['type']
        when 'boolean'
          {
            name: field['referenceName'],
            label: field['referenceName'].split('.').last.labelize,
            type: 'boolean'
          }
        when 'dateTime'
          {
            name: field['referenceName'],
            label: field['referenceName'].split('.').last.labelize,
            type: 'date_time'
          }
        when 'double'
          {
            name: field['referenceName'],
            label: field['referenceName'].split('.').last.labelize,
            type: 'number'
          }
        when 'integer'
          {
            name: field['referenceName'],
            label: field['referenceName'].split('.').last.labelize,
            type: 'integer'
          }
        else
          {
            name: field['referenceName'],
            label: field['referenceName'].split('.').last.labelize
          }
        end
      end&.compact.presence || []
    end,

    work_item_create_input: lambda do |input, action|
      toggle_schema = [
        { name: 'type',
          label: 'Work item type',
          control_type: 'select',
          pick_list: 'work_item_types_create',
          pick_list_params: { project: 'project' },
          extends_schema: true,
          change_on_blur: true,
          optional: false,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'type',
            control_type: 'text',
            label: 'Work item type',
            extends_schema: true,
            optional: false,
            type: 'string',
            hint: 'Please enter the work item type. <b>It is required to manually specify the ' \
                  'work item fields if this field contains a dynamic value.</b>'
          } },
        { name: 'System.AreaPath',
          label: 'Area path',
          control_type: 'select',
          pick_list: 'area_paths',
          hint: 'The area of the product for this work item.',
          pick_list_params: { project: 'project' },
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'System__2e__AreaPath',
            control_type: 'text',
            label: 'Area path',
            optional: true,
            type: 'string',
            hint: 'Please enter the area path.'
          } },
        { name: 'System.IterationPath',
          label: 'Iteration path',
          control_type: 'select',
          pick_list: 'iteration_paths',
          hint: 'The iteration for this work item.',
          pick_list_params: { project: 'project' },
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'System__2e__IterationPath',
            control_type: 'text',
            label: 'Iteration path',
            optional: true,
            type: 'string',
            hint: 'Please enter the iteration path.'
          } },
        { name: 'System.AssignedTo',
          label: 'Assigned to',
          control_type: 'select',
          pick_list: 'assigned_to',
          hint: 'The owner of the work item.',
          pick_list_params: { project: 'project' },
          sticky: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'System__2e__AssignedTo',
            control_type: 'text',
            label: 'Assigned to',
            optional: true,
            type: 'string',
            hint: 'Please enter the user name.'
          } }

      ]
      project_has_datapill = input['project']&.include?("{_('data.") ||
                             input['project']&.include?('pill_type')
      work_item_type_has_datapill = input['type']&.include?("{_('data.") ||
                                    input['type']&.include?('pill_type')

      schema = if project_has_datapill
                 string_schema = %w[type System.AreaPath System.IterationPath System.AssignedTo].
                                 map do |field|
                                   hint = if field == 'type'
                                            'e.g. <b>$Microsoft.VSTS.WorkItemTypes.' \
                                              'CodeReviewRequest</b>'
                                          end
                                   label = if field == 'type'
                                             'Work item type'
                                           else
                                             field.gsub('System.', '').labelize
                                           end
                                   {
                                     name: field,
                                     label: label,
                                     sticky: true,
                                     hint: hint
                                   }
                                 end.
                                 push({ name: 'custom_fields',
                                        label: 'Work item fields',
                                        sticky: true,
                                        extends_schema: true,
                                        schema_neutral: true,
                                        control_type: 'schema-designer',
                                        hint: 'Specify the work item fields using a sample JSON ' \
                                              'or build it manually using this schema designer.',
                                        sample_data_type: 'json_input' })

                 string_schema.concat(parse_json(input['custom_fields']) || [])
               elsif work_item_type_has_datapill
                 toggle_schema.
                   push({ name: 'custom_fields',
                          label: 'Work item fields',
                          sticky: true,
                          extends_schema: true,
                          schema_neutral: true,
                          control_type: 'schema-designer',
                          hint: 'Specify the work item fields using a sample JSON ' \
                                'or build it manually using this schema designer.',
                          sample_data_type: 'json_input' }).
                   concat(parse_json(input['custom_fields']) || [])
               else
                 toggle_schema.
                   concat(call('generate_work_item_input',
                               input.merge({ 'project_has_datapill' => project_has_datapill,
                                             'work_item_type_has_datapill' =>
                                             work_item_type_has_datapill }),
                               action))
               end
      call('format_schema', parse_json(schema.to_json))
    end,

    project_schema: lambda do |_input|
      [
        { name: 'id', label: 'Project ID' },
        { name: 'name' },
        { name: 'description' },
        { name: 'url' },
        { name: 'collection',
          type: 'object',
          properties: [
            { name: 'id', label: 'Collection ID' },
            { name: 'name' },
            { name: 'url' },
            { name: 'collectionUrl' }
          ] },
        { name: 'state' },
        { name: 'revision', type: 'integer' },
        { name: 'capabilities',
          type: 'object',
          properties: [
            { name: 'processTemplate',
              type: 'object',
              properties: [
                { name: 'templateTypeId' },
                { name: 'templateName' }
              ] },
            { name: 'versioncontrol',
              label: 'Version control',
              type: 'object',
              properties: [
                { name: 'sourceControlType' },
                { name: 'gitEnabled',
                  type: 'boolean' },
                { name: 'tfvcEnabled',
                  label: 'TFVC enabled',
                  type: 'boolean' }
              ] }
          ] },
        { name: 'visibility' },
        { name: 'lastUpdateTime',
          type: 'date_time',
          convert_output: 'date_time_conversion' },
        { name: 'defaultTeam',
          type: 'object',
          properties: [
            { name: 'id', label: 'Team ID' },
            { name: 'name' },
            { name: 'url' }
          ] }
      ]
    end,

    board_schema: lambda do |_input|
      [
        { name: 'id', label: 'Board ID' },
        { name: 'name' },
        { name: 'url' },
        { name: 'revision', type: 'integer' },
        { name: 'columns',
          type: 'array', of: 'object',
          properties: [
            { name: 'id', label: 'Collection ID' },
            { name: 'name' },
            { name: 'description' },
            { name: 'itemLimit', type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'isSplit',
              type: 'boolean',
              convert_output: 'boolean_conversion' },
            { name: 'stateMappings',
              type: 'object',
              properties: [
                { name: 'Epic' }
              ] },
            { name: 'columnType' }
          ] },
        { name: 'rows',
          type: 'array', of: 'object',
          properties: [
            { name: 'id', label: 'Row ID' },
            { name: 'name' },
            { name: 'color' }
          ] },
        { name: 'isValid',
          type: 'boolean',
          convert_output: 'boolean_conversion' },
        { name: 'allowedMappings',
          type: 'object',
          properties: [
            { name: 'Incoming',
              type: 'object',
              properties: [
                { name: 'Epic',
                  type: 'array', of: 'string' }
              ] },
            { name: 'InProgress',
              type: 'object',
              properties: [
                { name: 'Epic',
                  type: 'array', of: 'string' }
              ] },
            { name: 'Outgoing',
              type: 'object',
              properties: [
                { name: 'Epic',
                  type: 'array', of: 'string' }
              ] }
          ] },
        { name: 'canEdit',
          type: 'boolean',
          convert_output: 'boolean_conversion' },
        { name: 'fields',
          type: 'object',
          properties: [
            { name: 'columnField',
              type: 'object',
              properties: [
                { name: 'referenceName' },
                { name: 'url' }
              ] },
            { name: 'rowField',
              type: 'object',
              properties: [
                { name: 'referenceName' },
                { name: 'url' }
              ] },
            { name: 'doneField',
              type: 'object',
              properties: [
                { name: 'referenceName' },
                { name: 'url' }
              ] }
          ] }
      ]
    end,

    board_column_schema: lambda do |_input|
      [
        { name: 'name' }
      ]
    end,

    work_item_schema: lambda do |input|
      custom_fields = parse_json(input['custom_fields']).presence || []

      profile_properties = [
        { name: 'displayName' },
        { name: 'url', label: 'URL', control_type: 'url' },
        { name: 'id' },
        { name: 'uniqueName' },
        { name: 'imageUrl', label: 'Image URL',
          control_type: 'url' },
        { name: 'descriptor' }
      ]
      dynamic_schema = if input['project'].present?
                         call('generate_work_item_output', input)
                       else
                         []
                       end
      static_schema = [
        { name: 'System.Id', label: 'Work item ID', control_type: 'integer', type: 'integer' },
        { name: 'System.State', label: 'State' },
        { name: 'url', label: 'Work item URL' },
        { name: 'System.AreaLevel1', label: 'Area level 1' },
        { name: 'System.IterationLevel1', label: 'Iteration level 1' },
        { name: 'System.AssignedTo', label: 'Assigned to', type: 'object',
          properties: profile_properties },
        { name: 'System.CreatedBy', label: 'Created by', type: 'object',
          properties: profile_properties },
        { name: 'System.ChangedBy', label: 'Changed by', type: 'object',
          properties: profile_properties },
        { name: 'System.AuthorizedAs', label: 'Authorized as', type: 'object',
          properties: profile_properties },
        { name: 'Microsoft.VSTS.Common.ClosedBy', label: 'Closed by', type: 'object',
          properties: profile_properties },
        { name: 'Microsoft.VSTS.Common.ActivatedBy', label: 'Activated by', type: 'object',
          properties: profile_properties },
        { name: 'System.PersonId', label: 'Person ID', control_type: 'integer', type: 'integer' }
      ]
      final_schema = static_schema.concat(dynamic_schema).concat(custom_fields)

      call('format_schema', final_schema)
    end,

    build_search_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: '$top', label: 'Limit', type: 'integer', sticky: true,
          hint: 'The maximum number of builds to return.' },
        { name: 'branchName', sticky: true,
          hint: 'If specified, filters to builds that built ' \
                'branches that built this branch.' },
        { name: 'buildIds', label: 'Build IDs', sticky: true,
          hint: 'A comma-seperated list that specifies the IDs ' \
                'of builds to retrieve.' },
        { name: 'buildNumber', sticky: true,
          hint: 'If specified, filters to builds that match this build ' \
                'number. Append * to do a prefix search' },
        { name: 'continuationToken', sticky: true,
          hint: 'A continuation token, returned in search builds action, ' \
                'can be used to return the next set of builds.' },
        { name: 'definitions', sticky: true,
          hint: 'A comma-seperated list of definition IDs.' },
        { name: 'deletedFilter', sticky: true,
          control_type: 'select',
          pick_list: [
            ['Exclude deleted', 'excludeDeleted'],
            ['Include deleted', 'includeDeleted'],
            ['Only deleted', 'onlyDeleted']
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'deletedFilter', label: 'Deleted filter',
            type: 'string', control_type: 'text',
            optional: true,
            toggle_hint: 'Enter custom value',
            hint: 'Allowed values are excludeDeleted, includeDeleted, onlyDeleted'
          } },
        { name: 'maxBuildsPerDefinition', type: 'integer', sticky: true,
          hint: 'The maximum number of builds to return per definition.' },
        { name: 'maxTime', type: 'date_time', sticky: true },
        { name: 'minTime', type: 'date_time', sticky: true },
        { name: 'properties', type: 'array', of: 'string', sticky: true },
        { name: 'queryOrder', sticky: true,
          control_type: 'select',
          pick_list: [
            ['Finish time ascending', 'finishTimeAscending'],
            ['Finish time descending', 'finishTimeDescending'],
            ['Queue time ascending', 'queueTimeAscending'],
            ['Queue time descending', 'queueTimeDescending'],
            ['Start time ascending', 'startTimeAscending'],
            ['Start time descending', 'startTimeDescending']
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'queryOrder', label: 'Query order',
            type: 'string', control_type: 'text',
            optional: true,
            toggle_hint: 'Enter custom value',
            hint: 'Allowed values are finishTimeAscending, ' \
                  'finishTimeDescending, queueTimeAscending, queueTimeDescending, ' \
                  'startTimeAscending, startTimeDescending'
          } },
        { name: 'queues', type: 'integer', sticky: true,
          hint: 'A comma-seperated list of queue IDs.' },
        { name: 'reasonFilter', sticky: true,
          control_type: 'select',
          pick_list: [
            %w[All all],
            ['Batched CI', 'batchedCI'],
            ['Build completion', 'buildCompletion'],
            ['Check in shelveset', 'checkInShelveset'],
            ['Individual CI', 'individualCI'],
            %w[Manual manual],
            %w[None none],
            ['Pull request', 'pullRequest'],
            ['Resource trigger', 'resourceTrigger'],
            %w[Schedule schedule],
            ['Schedule forced', 'scheduleForced'],
            %w[Triggered triggered],
            ['User created', 'userCreated'],
            ['Validate shelveset', 'validateShelveset']
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'reasonFilter', label: 'Reason filter',
            type: 'string', control_type: 'text',
            optional: true,
            toggle_hint: 'Enter custom value',
            hint: 'Allowed values are all, manual, none, schedule, etc.'
          } },
        { name: 'repositoryId', sticky: true },
        { name: 'repositoryType', sticky: true },
        { name: 'requestedFor', sticky: true },
        { name: 'resultFilter', sticky: true,
          control_type: 'select',
          pick_list: [
            %w[Canceled canceled],
            %w[Failed failed],
            %w[None none],
            ['Partially succeeded', 'partiallySucceeded'],
            %w[Succeeded succeeded]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'resultFilter', label: 'Result filter',
            type: 'string', control_type: 'text',
            optional: true,
            toggle_hint: 'Enter custom value',
            hint: 'Allowed values are canceled, failed, none, ' \
                  'partiallySucceeded, succeeded'
          } },
        { name: 'statusFilter', sticky: true,
          control_type: 'select',
          pick_list: [
            %w[All all],
            %w[Cancelling cancelling],
            %w[Completed completed],
            %w[None none],
            ['In progress', 'inProgress'],
            ['Not started', 'notStarted'],
            %w[Postponed postponed]
          ],
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'statusFilter', label: 'Status filter',
            type: 'string', control_type: 'text',
            optional: true,
            toggle_hint: 'Enter custom value',
            hint: 'Allowed values are all, cancelling, completed, none, ' \
                  'inProgress, notStarted, postponed'
          } },
        { name: 'tagFilters', sticky: true,
          hint: 'A comma-seperated list of tags.' }
      ]
    end,

    build_get_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: 'id', label: 'Build ID', optional: false },
        { name: 'propertyFilters' }
      ]
    end,

    build_schema: lambda do |_input|
      [
        { name: 'id', label: 'Build ID', type: 'integer' },
        { name: 'buildNumber' },
        { name: 'buildNumberRevision', type: 'integer' },
        { name: 'agentSpecification', type: 'object',
          properties: [
            { name: 'identifier' }
          ] },
        { name: 'controller', type: 'object',
          properties: [
            { name: 'id', label: 'Controller ID', type: 'integer' },
            { name: 'name' },
            { name: 'description' },
            { name: 'status' },
            { name: 'uri', label: 'Controller URI' },
            { name: 'url', label: 'Controller URL' },
            { name: 'enabled', type: 'boolean' },
            { name: 'createdDate', type: 'date_time' },
            { name: 'updatedDate', type: 'date_time' }
          ] },
        { name: 'definition', type: 'object',
          properties: [
            { name: 'drafts', type: 'array', of: 'string' },
            { name: 'id',
              label: 'Definition ID',
              type: 'integer' },
            { name: 'name' },
            { name: 'uri', label: 'Definition URI' },
            { name: 'url', label: 'Definition URL' },
            { name: 'path' },
            { name: 'type' },
            { name: 'queueStatus' },
            { name: 'revision', type: 'integer' },
            { name: 'project', type: 'object',
              properties: [
                { name: 'id', label: 'Project ID' },
                { name: 'name' },
                { name: 'description' },
                { name: 'url', label: 'Project URL' },
                { name: 'state' },
                { name: 'revision', type: 'integer' },
                { name: 'visibility' },
                { name: 'lastUpdateTime', type: 'date_time' }
              ] }
          ] },
        { name: 'deleted', type: 'boolean' },
        { name: 'deletedDate', type: 'date_time' },
        { name: 'deletedBy', type: 'object',
          properties: [
            { name: 'displayName' },
            { name: 'url', label: 'URL' },
            { name: 'id', label: 'Deleted by ID' },
            { name: 'uniqueName' },
            { name: 'profileUrl', label: 'Profile URL' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'inactive', type: 'boolean' },
            { name: 'isAadIdentity', label: 'Is AAD identity', type: 'boolean' },
            { name: 'isContainer', type: 'boolean' },
            { name: 'isDeletedInOrigin', type: 'boolean' },
            { name: 'descriptor' },
            { name: 'directoryAlias' }
          ] },
        { name: 'deletedReason' },
        { name: 'status' },
        { name: 'result' },
        { name: 'demands', type: 'array', of: 'object',
          properties: [
            { name: 'name' },
            { name: 'value' }
          ] },
        { name: 'finishTime', type: 'date_time' },
        { name: 'queueTime', type: 'date_time' },
        { name: 'startTime', type: 'date_time' },
        { name: 'url', label: 'Build URL' },
        { name: 'properties', type: 'object',
          properties: [
            { name: 'keys', type: 'array', of: 'string' },
            { name: 'values', type: 'array', of: 'string' },
            { name: 'count', type: 'integer' },
            { name: 'item' }
          ] },
        { name: 'tags', type: 'array', of: 'string' },
        { name: 'validationResults', type: 'array', of: 'object',
          properties: [
            { name: 'message' },
            { name: 'result' }
          ] },
        { name: 'plans', type: 'array', of: 'object',
          properties: [
            { name: 'orchestrationType', type: 'integer' },
            { name: 'planId' }
          ] },
        { name: 'triggerInfo',
          type: 'object',
          properties: [
            { name: 'ci.sourceBranch', label: 'CI source branch' },
            { name: 'ci.sourceSha', label: 'CI source SHA' },
            { name: 'ci.message', label: 'CI message' }
          ] },
        { name: 'project', type: 'object',
          properties: [
            { name: 'id', label: 'Project ID' },
            { name: 'name' },
            { name: 'description' },
            { name: 'url', label: 'URL' },
            { name: 'state' },
            { name: 'revision', type: 'integer' },
            { name: 'visibility' },
            { name: 'defaultTeamImageUrl', label: 'Default team image URL' },
            { name: 'lastUpdateTime', type: 'date_time' }
          ] },
        { name: 'uri', label: 'URI' },
        { name: 'sourceBranch' },
        { name: 'sourceVersion' },
        { name: 'quality' },
        { name: 'queueOptions' },
        { name: 'queuePosition', type: 'integer' },
        { name: 'queue', type: 'object',
          properties: [
            { name: 'id',
              label: 'Queue ID',
              type: 'integer' },
            { name: 'name' },
            { name: 'pool', type: 'object',
              properties: [
                { name: 'id',
                  label: 'Pool ID',
                  type: 'integer' },
                { name: 'name' },
                { name: 'isHosted', type: 'boolean' }
              ] }
          ] },
        { name: 'priority' },
        { name: 'parameters' },
        { name: 'reason' },
        { name: 'requestedFor', type: 'object',
          properties: [
            { name: 'displayName' },
            { name: 'url', label: 'URL' },
            { name: 'id', label: 'Requested for ID' },
            { name: 'uniqueName' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'descriptor' }
          ] },
        { name: 'requestedBy', type: 'object',
          properties: [
            { name: 'displayName' },
            { name: 'url', label: 'URL' },
            { name: 'id', label: 'Requested by ID' },
            { name: 'uniqueName' },
            { name: 'profileUrl', label: 'Profile URL' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'inactive', type: 'boolean' },
            { name: 'isAadIdentity', type: 'boolean' },
            { name: 'isContainer', type: 'boolean' },
            { name: 'isDeletedInOrigin', type: 'boolean' },
            { name: 'descriptor' },
            { name: 'directoryAlias' }
          ] },
        { name: 'lastChangedDate', type: 'date_time' },
        { name: 'lastChangedBy', type: 'object',
          properties: [
            { name: 'displayName' },
            { name: 'url', label: 'URL' },
            { name: 'id', label: 'Last changed by ID' },
            { name: 'uniqueName' },
            { name: 'profileUrl', label: 'Profile URL' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'inactive', type: 'boolean' },
            { name: 'isAadIdentity', type: 'boolean' },
            { name: 'isContainer', type: 'boolean' },
            { name: 'isDeletedInOrigin', type: 'boolean' },
            { name: 'descriptor' },
            { name: 'directoryAlias' }
          ] },
        { name: 'orchestrationPlan', type: 'object',
          properties: [
            { name: 'planId' }
          ] },
        { name: 'logs', type: 'object',
          properties: [
            { name: 'id', label: 'Log ID', type: 'integer' },
            { name: 'type' },
            { name: 'url', label: 'URL' }
          ] },
        { name: 'repository', type: 'object',
          properties: [
            { name: 'id', label: 'Repository ID' },
            { name: 'type' },
            { name: 'name' },
            { name: 'url', label: 'URL' },
            { name: 'clean' },
            { name: 'defaultBranch' },
            { name: 'rootFolder' },
            { name: 'checkoutSubmodules', type: 'boolean' },
            { name: 'properties' }
          ] },
        { name: 'retainedByRelease', type: 'boolean' },
        { name: 'templateParameters' },
        { name: 'triggeredByBuild' },
        { name: 'appendCommitMessageToRunName', type: 'boolean' }
      ]
    end,

    build_log_search_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: 'build_id', label: 'Build ID', optional: false }
      ]
    end,

    build_log_get_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: 'build_id', label: 'Build ID', optional: false },
        { name: 'id', label: 'Build log ID', optional: false },
        { name: 'startLine', type: 'integer', sticky: true,
          convert_input: 'integer_conversion' },
        { name: 'endLine', type: 'integer', sticky: true,
          convert_input: 'integer_conversion' }
      ]
    end,

    build_log_schema: lambda do |_input|
      [
        { name: 'id', label: 'Build log ID', type: 'integer' },
        { name: 'type' },
        { name: 'url', label: 'Build log URL' },
        { name: 'lineCount', type: 'integer' },
        { name: 'createdOn', type: 'date_time' },
        { name: 'lastChangedOn', type: 'date_time' }
      ]
    end,

    run_search_input: lambda do
      [
        { name: 'project', optional: false,
          control_type: 'select',
          pick_list: 'projects',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'project', label: 'Project',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Enter project name'
          } },
        { name: 'pipeline_id', optional: false,
          control_type: 'select',
          pick_list: 'pipelines',
          pick_list_params: { project: 'project' },
          hint: 'Please select the pipeline ID',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'pipeline_id', label: 'Pipeline ID',
            type: 'string', control_type: 'text',
            optional: false,
            toggle_hint: 'Enter custom value',
            hint: 'Provide the pipeline ID. E.g. 5'
          } }
      ]
    end,

    run_get_input: lambda do
      call('run_search_input').
        push({ name: 'id', label: 'Run ID', optional: false })
    end,

    run_schema: lambda do |_input|
      [
        { name: 'id', label: 'Run ID', type: 'integer' },
        { name: 'name' },
        { name: 'url', label: 'Run URL' },
        { name: 'pipeline', type: 'object',
          properties: [
            { name: 'id', label: 'Pipeline ID', type: 'integer' },
            { name: 'name' },
            { name: 'url', label: 'Pipeline URL' },
            { name: 'state' },
            { name: 'folder' },
            { name: 'revision', type: 'integer' }
          ] },
        { name: 'templateParameters' },
        { name: 'createdDate', type: 'date_time' },
        { name: 'finishedDate', type: 'date_time' },
        { name: 'finalYaml', label: 'Final YAML' },
        { name: 'resources', type: 'object',
          properties: [
            { name: 'repositories', type: 'object',
              properties: [
                { name: 'self', type: 'object',
                  properties: [
                    { name: 'repository', type: 'object',
                      properties: [
                        { name: 'id', label: 'Repository ID' },
                        { name: 'fullName' },
                        { name: 'type' },
                        { name: 'connection',
                          type: 'object',
                          properties: [
                            { name: 'id', label: 'Connection ID' }
                          ] }
                      ] },
                    { name: 'refName' },
                    { name: 'version' }
                  ] }
              ] }
          ] },
        { name: 'result' },
        { name: 'state' },
        { name: 'variables' }
      ]
    end,

    build_completed_schema: lambda do
      [
        { name: 'uri', label: 'Build URI' },
        { name: 'id', label: 'Build ID', type: 'integer' },
        { name: 'buildNumber' },
        { name: 'url', label: 'Build URL' },
        { name: 'startTime', type: 'date_time' },
        { name: 'finishTime', type: 'date_time' },
        { name: 'reason' },
        { name: 'status' },
        { name: 'dropLocation' },
        { name: 'drop', type: 'object',
          properties: [
            { name: 'location' },
            { name: 'type' },
            { name: 'url', label: 'Drop URL' },
            { name: 'downloadUrl', label: 'Download URL' }
          ] },
        { name: 'log', type: 'object',
          properties: [
            { name: 'type' },
            { name: 'url', label: 'Log URL' },
            { name: 'downloadUrl', label: 'Download URL' }
          ] },
        { name: 'sourceGetVersion' },
        { name: 'lastChangedBy', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' },
            { name: 'url', label: 'URL' },
            { name: 'imageUrl', label: 'Image URL' }
          ] },
        { name: 'retainIndefinitely', type: 'boolean' },
        { name: 'hasDiagnostics', type: 'boolean' },
        { name: 'definition', type: 'object',
          properties: [
            { name: 'batchSize', type: 'integer' },
            { name: 'triggerType' },
            { name: 'definitionType' },
            { name: 'id', label: 'Definition ID', type: 'integer' },
            { name: 'name' },
            { name: 'url', label: 'Definition URL' }
          ] },
        { name: 'queue', type: 'object',
          properties: [
            { name: 'queueType' },
            { name: 'id', label: 'Queue ID', type: 'integer' },
            { name: 'name' },
            { name: 'url', label: 'Queue URL' }
          ] },
        { name: 'requests', type: 'array', of: 'object',
          properties: [
            { name: 'id', label: 'Request ID', type: 'integer' },
            { name: 'url', label: 'Request URL' },
            { name: 'requestedFor', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'displayName' },
                { name: 'uniqueName' },
                { name: 'url', label: 'URL' },
                { name: 'imageUrl', label: 'Image URL' }
              ] }
          ] }
      ]
    end,

    ms_vss_release_release_created_event_schema: lambda do
      [
        { name: 'id', label: 'Release ID' },
        { name: 'url', label: 'Release URL' },
        { name: 'project', type: 'object',
          properties: [
            { name: 'id', label: 'Project ID' },
            { name: 'name' }
          ] },
        { name: 'release', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'name' },
            { name: 'status' },
            { name: 'createdOn', type: 'date_time' },
            { name: 'modifiedOn', type: 'date_time' },
            { name: 'modifiedBy', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'displayName' }
              ] },
            { name: 'createdBy', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'displayName' }
              ] },
            { name: 'environments', type: 'array', of: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'releaseId', type: 'integer' },
                { name: 'name' },
                { name: 'status' },
                { name: 'variables', type: 'object',
                  properties: [] },
                { name: 'preDeployApprovals',
                  type: 'array', of: 'string' },
                { name: 'postDeployApprovals',
                  type: 'array', of: 'string' },
                { name: 'preApprovalsSnapshot', type: 'object',
                  properties: [
                    { name: 'approvals', type: 'array', of: 'string' },
                    { name: 'approvalOptions', type: 'object',
                      properties: [
                        { name: 'requiredApproverCount', type: 'integer' },
                        { name: 'releaseCreatorCanBeApprover',
                          type: 'boolean' }
                      ] }
                  ] },
                { name: 'postApprovalsSnapshot', type: 'object',
                  properties: [
                    { name: 'approvals', type: 'array', of: 'string' }
                  ] },
                { name: 'deploySteps', type: 'array', of: 'string' },
                { name: 'rank', type: 'integer' },
                { name: 'definitionEnvironmentId', type: 'integer' },
                { name: 'queueId', type: 'integer' },
                { name: 'environmentOptions', type: 'object',
                  properties: [
                    { name: 'emailNotificationType' },
                    { name: 'emailRecipients' },
                    { name: 'skipArtifactsDownload', type: 'boolean' },
                    { name: 'timeoutInMinutes', type: 'integer' },
                    { name: 'enableAccessToken', type: 'boolean' }
                  ] },
                { name: 'demands', type: 'array', of: 'string' },
                { name: 'conditions', type: 'array', of: 'string' },
                { name: 'modifiedOn', type: 'date_time' },
                { name: 'workflowTasks', type: 'array', of: 'object',
                  properties: [
                    { name: 'taskId' },
                    { name: 'version' },
                    { name: 'name' },
                    { name: 'enabled', type: 'boolean' },
                    { name: 'alwaysRun', type: 'boolean' },
                    { name: 'continueOnError', type: 'boolean' },
                    { name: 'timeoutInMinutes', type: 'integer' },
                    { name: 'definitionType' },
                    { name: 'inputs', type: 'object',
                      properties: [
                        { name: 'ConnectedServiceName' },
                        { name: 'WebSiteName' },
                        { name: 'WebSiteLocation' },
                        { name: 'Slot' },
                        { name: 'Package' }
                      ] }
                  ] },
                { name: 'deployPhasesSnapshot',
                  type: 'array', of: 'string' },
                { name: 'owner', type: 'object',
                  properties: [
                    { name: 'id' },
                    { name: 'displayName' }
                  ] },
                { name: 'scheduledDeploymentTime', type: 'date_time' },
                { name: 'schedules', type: 'array', of: 'string' },
                { name: 'release', type: 'object',
                  properties: [
                    { name: 'id', label: 'Release ID', type: 'integer' },
                    { name: 'name' },
                    { name: 'url', label: 'Release URL' }
                  ] }
              ] },
            { name: 'variables', type: 'object', properties: [] },
            { name: 'artifacts', type: 'array', of: 'object',
              properties: [
                { name: 'sourceId' },
                { name: 'type' },
                { name: 'alias' },
                { name: 'definitionReference', type: 'object',
                  properties: [
                    { name: 'Definition', type: 'object',
                      properties: [
                        { name: 'id' },
                        { name: 'name' }
                      ] },
                    { name: 'Project', type: 'object',
                      properties: [
                        { name: 'id' },
                        { name: 'name' }
                      ] }
                  ] },
                { name: 'isPrimary', type: 'boolean' }
              ] },
            { name: 'releaseDefinition', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' },
                { name: 'url', label: 'URL' }
              ] },
            { name: 'description' },
            { name: 'reason' },
            { name: 'releaseNameFormat' },
            { name: 'keepForever', type: 'boolean' },
            { name: 'definitionSnapshotRevision', type: 'integer' },
            { name: 'comment' },
            { name: 'logsContainerUrl', label: 'Logs container URL' }
          ] }
      ]
    end,
    ms_vss_release_release_abandoned_event_schema: lambda do
      call('ms_vss_release_release_created_event_schema')
    end,
    ms_vss_release_deployment_approval_completed_event_schema: lambda do
      call('ms_vss_release_release_created_event_schema').push(
        { name: 'approval', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'revision', type: 'integer' },
            { name: 'approver', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'displayName' }
              ] },
            { name: 'approvedBy', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'displayName' }
              ] },
            { name: 'approvalType' },
            { name: 'createdOn', type: 'date_time' },
            { name: 'modifiedOn', type: 'date_time' },
            { name: 'status' },
            { name: 'comments' },
            { name: 'isAutomated', type: 'boolean' },
            { name: 'isNotificationOn', type: 'boolean' },
            { name: 'trialNumber', type: 'integer' },
            { name: 'attempt', type: 'integer' },
            { name: 'rank', type: 'integer' },
            { name: 'release', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' }
              ] },
            { name: 'releaseDefinition', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' },
                { name: 'url', label: 'URL' }
              ] },
            { name: 'releaseEnvironment', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' }
              ] }
          ] }
      )
    end,
    ms_vss_release_deployment_approval_pending_event_schema: lambda do
      call('ms_vss_release_deployment_approval_completed_event_schema')
    end,
    ms_vss_release_deployment_completed_event_schema: lambda do
      call('ms_vss_release_release_created_event_schema').push(
        { name: 'environment', type: 'object',
          properties: [
            { name: 'id', type: 'integer' },
            { name: 'releaseId', type: 'integer' },
            { name: 'name' },
            { name: 'status' },
            { name: 'variables', type: 'object', properties: [] },
            { name: 'variableGroups', type: 'array', of: 'string' },
            { name: 'preDeployApprovals', type: 'array', of: 'string' },
            { name: 'postDeployApprovals', type: 'array', of: 'string' },
            { name: 'preApprovalsSnapshot', type: 'object',
              properties: [
                { name: 'approvals', type: 'array', of: 'string' },
                { name: 'approvalOptions', type: 'object',
                  properties: [
                    { name: 'requiredApproverCount', type: 'integer' },
                    { name: 'releaseCreatorCanBeApprover', type: 'boolean' },
                    { name: 'autoTriggeredAndPreviousEnvironmentApprovedCanBeSkipped',
                      type: 'boolean' },
                    { name: 'enforceIdentityRevalidation',
                      type: 'boolean' },
                    { name: 'timeoutInMinutes',
                      type: 'integer' },
                    { name: 'executionOrder' }
                  ] }
              ] },
            { name: 'postApprovalsSnapshot', type: 'object',
              properties: [
                { name: 'approvals', type: 'array', of: 'string' }
              ] },
            { name: 'deploySteps', type: 'array', of: 'string' },
            { name: 'rank', type: 'integer' },
            { name: 'definitionEnvironmentId', type: 'integer' },
            { name: 'queueId', type: 'integer' },
            { name: 'environmentOptions', type: 'object',
              properties: [
                { name: 'emailNotificationType' },
                { name: 'emailRecipients' },
                { name: 'skipArtifactsDownload',
                  type: 'boolean' },
                { name: 'timeoutInMinutes', type: 'integer' },
                { name: 'enableAccessToken', type: 'boolean' },
                { name: 'publishDeploymentStatus',
                  type: 'boolean' },
                { name: 'badgeEnabled', type: 'boolean' },
                { name: 'autoLinkWorkItems', type: 'boolean' },
                { name: 'pullRequestDeploymentEnabled',
                  type: 'boolean' }
              ] },
            { name: 'demands', type: 'array', of: 'string' },
            { name: 'conditions', type: 'array', of: 'string' },
            { name: 'modifiedOn', type: 'date_time' },
            { name: 'workflowTasks', type: 'array', of: 'string' },
            { name: 'deployPhasesSnapshot', type: 'array', of: 'string' },
            { name: 'owner', type: 'object',
              properties: [
                { name: 'displayName' },
                { name: 'id' }
              ] },
            { name: 'scheduledDeploymentTime', type: 'date_time' },
            { name: 'schedules', type: 'array', of: 'string' },
            { name: 'release', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'name' }
              ] },
            { name: 'preDeploymentGatesSnapshot', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'gatesOptions' },
                { name: 'gates', type: 'array', of: 'string' }
              ] },
            { name: 'postDeploymentGatesSnapshot', type: 'object',
              properties: [
                { name: 'id', type: 'integer' },
                { name: 'gatesOptions' },
                { name: 'gates', type: 'array', of: 'string' }
              ] }
          ] }
      )
    end,
    ms_vss_release_deployment_started_event_schema: lambda do
      call('ms_vss_release_deployment_completed_event_schema')
    end,
    ms_vss_pipelines_run_state_changed_event_schema: lambda do
      [
        { name: 'run', type: 'object',
          properties: [
            { name: 'pipeline', type: 'object',
              properties: [
                { name: 'url', label: 'Pipeline URL' },
                { name: 'id', type: 'integer' },
                { name: 'revision', type: 'integer' },
                { name: 'name' },
                { name: 'folder' }
              ] },
            { name: 'state' },
            { name: 'result' },
            { name: 'createdDate', type: 'date_time' },
            { name: 'finishedDate', type: 'date_time' },
            { name: 'url', label: 'Run URL' },
            { name: 'id', label: 'Run ID', type: 'integer' },
            { name: 'name' }
          ] },
        { name: 'pipeline', type: 'object',
          properties: [
            { name: 'url', label: 'Pipeline URL' },
            { name: 'id', label: 'Pipeline ID', type: 'integer' },
            { name: 'revision', type: 'integer' },
            { name: 'name' },
            { name: 'folder' }
          ] }
      ]
    end,
    ms_vss_pipelines_stage_state_changed_event_schema: lambda do
      call('ms_vss_pipelines_run_state_changed_event_schema').push(
        { name: 'stage', type: 'object',
          properties: [
            { name: 'id', label: 'Stage ID' },
            { name: 'name' },
            { name: 'displayName' },
            { name: 'state' },
            { name: 'result' }
          ] }
      )
    end,
    ms_vss_pipelinechecks_events_approval_pending_schema: lambda do
      [
        { name: 'approval', type: 'object',
          properties: [
            { name: 'id', label: 'Approval ID' },
            { name: 'steps', type: 'array', of: 'object',
              properties: [
                { name: 'assignedApprover', type: 'object',
                  properties: [
                    { name: 'displayName' },
                    { name: 'id' }
                  ] },
                { name: 'status' },
                { name: 'comment' },
                { name: 'initiatedOn', type: 'date_time' }
              ] },
            { name: 'status' },
            { name: 'createdOn', type: 'date_time' },
            { name: 'lastModifiedOn', type: 'date_time' },
            { name: 'instructions' },
            { name: 'minRequiredApprovers', type: 'integer' },
            { name: 'blockedApprovers', type: 'array', of: 'object',
              properties: [
                { name: 'displayName' },
                { name: 'id' }
              ] }
          ] },
        { name: 'projectId' },
        { name: 'pipeline' },
        { name: 'stage' },
        { name: 'run' },
        { name: 'resource' },
        { name: 'id', type: 'integer' },
        { name: 'url', label: 'URL' },
        { name: 'stageName' },
        { name: 'attemptId', type: 'integer' }
      ]
    end,
    ms_vss_pipelinechecks_events_approval_completed_schema: lambda do
      call('ms_vss_pipelinechecks_events_approval_pending_schema')
    end,
    tfvc_checkin_schema: lambda do
      [
        { name: 'changesetId', type: 'integer' },
        { name: 'url', label: 'URL' },
        { name: 'author', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' }
          ] },
        { name: 'checkedInBy', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' }
          ] },
        { name: 'createdDate', type: 'date_time' },
        { name: 'comment' }
      ]
    end,
    git_push_schema: lambda do
      [
        { name: 'commits', type: 'array', of: 'object',
          properties: [
            { name: 'commitId' },
            { name: 'author', type: 'object',
              properties: [
                { name: 'name' },
                { name: 'email' },
                { name: 'date', type: 'date_time' }
              ] },
            { name: 'committer', type: 'object',
              properties: [
                { name: 'name' },
                { name: 'email' },
                { name: 'date', type: 'date_time' }
              ] },
            { name: 'comment' },
            { name: 'url', label: 'URL' }
          ] },
        { name: 'refUpdates', type: 'array', of: 'object',
          properties: [
            { name: 'name' },
            { name: 'oldObjectId' },
            { name: 'newObjectId' }
          ] },
        { name: 'repository', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'name' },
            { name: 'url', label: 'Repository URL' },
            { name: 'project', type: 'object',
              properties: [
                { name: 'id', label: 'Project ID' },
                { name: 'name' },
                { name: 'url', label: 'Project URL' },
                { name: 'state' }
              ] },
            { name: 'defaultBranch' },
            { name: 'remoteUrl', label: 'Remote URL' }
          ] },
        { name: 'pushedBy', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' }
          ] },
        { name: 'pushId', type: 'integer' },
        { name: 'date', type: 'date_time' },
        { name: 'url', label: 'URL' }
      ]
    end,
    git_pullrequest_created_schema: lambda do
      [
        { name: 'repository', type: 'object',
          properties: [
            { name: 'id', label: 'Repository ID' },
            { name: 'name' },
            { name: 'url', label: 'Repository URL' },
            { name: 'project', type: 'object',
              properties: [
                { name: 'id', label: 'Project ID' },
                { name: 'name' },
                { name: 'url', label: 'Project URL' },
                { name: 'state' }
              ] },
            { name: 'defaultBranch' },
            { name: 'remoteUrl', label: 'Remote URL' }
          ] },
        { name: 'pullRequestId', type: 'integer' },
        { name: 'status' },
        { name: 'createdBy', type: 'object',
          properties: [
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' },
            { name: 'url', label: 'URL' },
            { name: 'imageUrl', label: 'Image URL' }
          ] },
        { name: 'creationDate', type: 'date_time' },
        { name: 'title' },
        { name: 'description' },
        { name: 'sourceRefName' },
        { name: 'targetRefName' },
        { name: 'mergeStatus' },
        { name: 'mergeId' },
        { name: 'lastMergeSourceCommit', type: 'object',
          properties: [
            { name: 'commitId' },
            { name: 'url', label: 'URL' }
          ] },
        { name: 'lastMergeTargetCommit', type: 'object',
          properties: [
            { name: 'commitId' },
            { name: 'url', label: 'URL' }
          ] },
        { name: 'lastMergeCommit', type: 'object',
          properties: [
            { name: 'commitId' },
            { name: 'url', label: 'URL' }
          ] },
        { name: 'reviewers', type: 'array', of: 'object',
          properties: [
            { name: 'reviewerUrl', label: 'Reviewer URL' },
            { name: 'vote', type: 'integer' },
            { name: 'id' },
            { name: 'displayName' },
            { name: 'uniqueName' },
            { name: 'url', label: 'URL' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'isContainer', type: 'boolean' }
          ] },
        { name: 'url', label: 'URL' }
      ]
    end,
    git_pullrequest_merged_schema: lambda do
      call('git_pullrequest_created_schema').push(
        { name: 'closedDate', type: 'date_time' }
      )
    end,
    git_pullrequest_updated_schema: lambda do
      call('git_pullrequest_created_schema').push(
        { name: 'closedDate', type: 'date_time' },
        { name: 'commits', type: 'array', of: 'object',
          properties: [
            { name: 'commitId' },
            { name: 'url', label: 'URL' }
          ] }
      )
    end,
    workitem_commented_schema: lambda do
      [
        { name: 'id', label: 'Work item ID', type: 'integer' },
        { name: 'url', label: 'Work item URL' },
        { name: 'rev', type: 'integer' },
        { name: 'fields', type: 'object',
          properties: [
            { name: 'System_AreaPath' },
            { name: 'System_TeamProject' },
            { name: 'System_IterationPath' },
            { name: 'System_WorkItemType' },
            { name: 'System_State' },
            { name: 'System_Reason' },
            { name: 'System_CreatedDate', type: 'date_time' },
            { name: 'System_CreatedBy' },
            { name: 'System_ChangedDate', type: 'date_time' },
            { name: 'System_ChangedBy' },
            { name: 'System_Title' },
            { name: 'System_History' },
            { name: 'Microsoft_Azure_DevOps_Services_Common_Severity' },
            { name: 'WEF_EB329F44FE5F4A94ACB1DA153FDF38BA_Kanban_Column' }
          ] }
      ]
    end,
    workitem_created_schema: lambda do
      [
        { name: 'id', label: 'Work item ID', type: 'integer' },
        { name: 'url', label: 'Work item URL' },
        { name: 'rev', type: 'integer' },
        { name: 'fields', type: 'object',
          properties: [
            { name: 'System_AreaPath' },
            { name: 'System_TeamProject' },
            { name: 'System_IterationPath' },
            { name: 'System_WorkItemType' },
            { name: 'System_State' },
            { name: 'System_Reason' },
            { name: 'System_CreatedDate', type: 'date_time' },
            { name: 'System_CreatedBy' },
            { name: 'System_ChangedDate', type: 'date_time' },
            { name: 'System_ChangedBy' },
            { name: 'System_Title' },
            { name: 'Microsoft_Azure_DevOps_Services_Common_Severity' },
            { name: 'WEF_EB329F44FE5F4A94ACB1DA153FDF38BA_Kanban_Column' }
          ] },
        { name: 'relations',
          type: 'object',
          properties: [
            { name: 'rel' },
            { name: 'url' },
            { name: 'attributes',
              type: 'object',
              properties: [
                { name: 'id', label: 'Attribute ID',
                  type: 'integer' },
                { name: 'name' },
                { name: 'comment' },
                { name: 'authorizedDate',
                  type: 'date_time' },
                { name: 'resourceCreatedDate',
                  type: 'date_time' },
                { name: 'resourceModifiedDate',
                  type: 'date_time' },
                { name: 'revisedDate',
                  type: 'date_time' },
                { name: 'resourceSize',
                  type: 'integer' }
              ] }
          ] }
      ]
    end,
    workitem_deleted_schema: lambda do
      call('workitem_created_schema')
    end,
    workitem_restored_schema: lambda do
      call('workitem_created_schema')
    end,
    workitem_updated_schema: lambda do
      [
        { name: 'id', label: 'ID', type: 'integer' },
        { name: 'url', label: 'Work item URL' },
        { name: 'workItemId', type: 'integer', label: 'Work item ID' },
        { name: 'rev', type: 'integer' },
        { name: 'revisedBy',
          type: 'object',
          properties: [
            { name: 'id' },
            { name: 'name' },
            { name: 'displayName' },
            { name: 'url' },
            { name: 'uniqueName' },
            { name: 'imageUrl', label: 'Image URL' },
            { name: 'descriptor' }
          ] },
        { name: 'revisedDate', type: 'date_time' },
        { name: 'fields', type: 'object',
          properties: [
            { name: 'System_Rev', type: 'object',
              properties: call('value_update_schema') },
            { name: 'System_AuthorizedDate', type: 'object',
              properties: call('date_value_update_schema') },
            { name: 'System_RevisedDate', type: 'object',
              properties: call('date_value_update_schema') },
            { name: 'System_State', type: 'object',
              properties: call('value_update_schema') },
            { name: 'System_Reason', type: 'object',
              properties: call('value_update_schema') },
            { name: 'System_AssignedTo', type: 'object',
              properties: call('value_update_schema') },
            { name: 'System_ChangedDate', type: 'object',
              properties: call('date_value_update_schema') },
            { name: 'System_Watermark', type: 'object',
              properties: call('value_update_schema') },
            { name: 'Microsoft_Azure_DevOps_Services_Common_Severity', type: 'object',
              properties: call('value_update_schema') }
          ] },
        { name: 'relations',
          type: 'object',
          properties: [
            { name: 'added',
              type: 'array', of: 'object',
              properties: [
                { name: 'rel' },
                { name: 'url' },
                { name: 'attributes',
                  type: 'object',
                  properties: [
                    { name: 'id', label: 'Attribute ID',
                      type: 'integer' },
                    { name: 'name' },
                    { name: 'comment' },
                    { name: 'authorizedDate',
                      type: 'date_time' },
                    { name: 'resourceCreatedDate',
                      type: 'date_time' },
                    { name: 'resourceModifiedDate',
                      type: 'date_time' },
                    { name: 'revisedDate',
                      type: 'date_time' },
                    { name: 'resourceSize',
                      type: 'integer' }
                  ] }
              ] }
          ] },
        { name: 'revision', type: 'object',
          properties: call('workitem_created_schema') }
      ]
    end,

    value_update_schema: lambda do
      [
        { name: 'oldValue' },
        { name: 'newValue' }
      ]
    end,

    date_value_update_schema: lambda do
      [
        { name: 'oldValue' },
        { name: 'newValue' }
      ]
    end,
    workitem_created_updated_trigger_schema: lambda do
      profile_properties = [
        { name: 'displayName' },
        { name: 'url', label: 'URL' },
        { name: 'id' },
        { name: 'uniqueName' },
        { name: 'imageUrl', label: 'Image URL' },
        { name: 'descriptor' },
        { name: '_links', label: 'Links', type: 'object', properties: [
          { name: 'avatar', type: 'object', properties: [
            { name: 'href' }
          ] }
        ] }
      ]
      [
        { name: 'id', label: 'Work item ID', type: 'integer' },
        { name: 'url', label: 'Work item URL' },
        { name: 'rev', label: 'Revision number', type: 'integer' },
        { name: 'fields', type: 'object',
          properties: [
            { name: 'System.AreaPath', label: 'Area path' },
            { name: 'System.TeamProject', label: 'Team project' },
            { name: 'System.IterationPath', label: 'Iteration path' },
            { name: 'System.WorkItemType', label: 'Work item type' },
            { name: 'System.State', label: 'State' },
            { name: 'System.Reason', label: 'Reason' },
            { name: 'System.CreatedDate', type: 'date_time', label: 'Created date' },
            { name: 'System.ChangedDate', type: 'date_time', label: 'Changed date' },
            { name: 'System.AssignedTo', label: 'Assigned to', type: 'object',
              properties: profile_properties },
            { name: 'System.CreatedBy', label: 'Created by', type: 'object',
              properties: profile_properties },
            { name: 'System.ChangedBy', label: 'Changed by', type: 'object',
              properties: profile_properties },
            { name: 'System.AuthorizedAs', label: 'Authorized as', type: 'object',
              properties: profile_properties },
            { name: 'Microsoft.VSTS.Common.ClosedBy', label: 'Closed by', type: 'object',
              properties: profile_properties },
            { name: 'Microsoft.VSTS.Common.ActivatedBy', label: 'Activate by', type: 'object',
              properties: profile_properties },
            { name: 'System.CommentCount', label: 'Comment count' },
            { name: 'Microsoft.VSTS.Common.StateChangeDate', label: 'State change date' },
            { name: 'Microsoft.VSTS.Common.Priority', label: 'Priority' },
            { name: 'System.Title', label: 'Title' },
            { name: 'System.Description', label: 'Description' },
            { name: 'Microsoft.Azure.DevOps.Services.Common_Severity', label: 'Severity' },
            { name: 'Microsoft.VSTS.Common.ActivatedDate', label: 'Activated date' },
            { name: 'Microsoft.VSTS.Common.ClosedDate', label: 'Closed date' }
          ] }
      ]
    end,
    sample_created_updated_workitem_trigger_output: lambda do
      {
        work_items: [
          {
            id: 297,
            rev: 1,
            fields: {
              System__2e__AreaPath: 'Fabrikam-Fiber-Git',
              System__2e__TeamProject: 'Fabrikam-Fiber-Git',
              System__2e__IterationPath: 'Fabrikam-Fiber-Git',
              System__2e__WorkItemType: 'Product Backlog Item',
              System__2e__State: 'New',
              System__2e__ChangedDate: '2025-03-18T04:54:38.913Z',
              System__2e__Reason: 'New task required',
              System__2e__CreatedDate: '2014-12-29T20:49:20.77Z',
              System__2e__CreatedBy: {
                displayName: 'Jamal Hartnett',
                url: 'https://vssps.dev.azure.com/fabrikam/_apis/Identities/d291b0c4-xxxxxxx',
                _links: {
                  avatar: {
                    href: 'https://dev.azure.com/mseng/_apis/GraphProfile/MemberAvatars/aad.YTkzODFkODYtxxxxxx'
                  }
                },
                id: 'd291b0c4-a05c-4ea6-8df1-4b41xxxx',
                uniqueName: 'fabrikamfiber4@hotmail.com',
                imageUrl: 'https://dev.azure.com/fabrikam/_api/_common/identityImage?id=d291b0c4-axxxxx',
                descriptor: 'aad.YTkzODFkODYtNTaxxxxxx'
              },
              System__2e__ChangedDate: '2014-12-29T20:49:20.77Z',
              System__2e__ChangedBy: {
                displayName: 'Jamal Hartnett',
                url: 'https://vssps.dev.azure.com/fabrikam/_apis/Identities/d291b0c4axxxxxx',
                _links: {
                  avatar: {
                    href: 'https://dev.azure.com/mseng/_apis/GraphProfile/MemberAvatars/aad.YTkzODxxxxxxx'
                  }
                },
                id: 'd291b0c4-a05c-4ea6-8df1-4b41d5f39eff',
                uniqueName: 'fabrikamfiber4@hotmail.com',
                imageUrl: 'https://dev.azure.com/fabrikam/_api/_common/identityImage?id=d291b0c4-axxxxxxx',
                descriptor: 'aad.YTkzODFkODYtNTYxYSxxxxxxx'
              },
              System__2e__CommentCount: 0,
              System__2e__Title: 'Customer can sign in using their Microsoft Account',
              Microsoft__2e__VSTS__2e__Scheduling__2e__Effort: 8,
              Microsoft__2e__VSTS__2e__Common__2e__StateChangeDate: '2025-03-18T04:54:38.913Z',
              Microsoft__2e__VSTS__2e__Common__2e__Priority: 2,
              WEF__2e__6CB513B6E70E43499D9FC94E5BBFB784__2e__Kanban__2e__Column: 'New',
              System__2e__Description: 'Authorization for users with Microsoft accounts'
            },
            url: 'https://dev.azure.com/fabrikam/_apis/wit/workItems/297'
          }
        ]
      }
    end
  },

  object_definitions: {
    custom_action_input: {
      fields: lambda do |connection, config_fields|
        verb = config_fields['verb']
        input_schema = parse_json(config_fields.dig('input', 'schema') || '[]')
        data_props =
          input_schema.map do |field|
            if config_fields['request_type'] == 'multipart' &&
               field['binary_content'] == 'true'
              field['type'] = 'object'
              field['properties'] = [
                { name: 'file_content', label: 'File contents', optional: false },
                {
                  name: 'content_type',
                  default: 'text/plain',
                  sticky: true
                },
                { name: 'original_filename', sticky: true }
              ]
            end
            field
          end
        data_props = call('make_schema_builder_fields_sticky', data_props)
        input_data =
          if input_schema.present?
            if input_schema.dig(0, 'type') == 'array' &&
               input_schema.dig(0, 'details', 'fake_array')
              {
                name: 'data',
                type: 'array',
                of: 'object',
                properties: data_props.dig(0, 'properties')
              }
            else
              { name: 'data', type: 'object', properties: data_props }
            end
          end

        [
          {
            name: 'path',
            hint: "Base URI is <b>https://dev.azure.com/#{connection['organization']}/" \
                  '</b> - path will be appended to this URI. Use absolute URI to ' \
                  'override this base URI.',
            optional: false
          },
          if %w[post put patch].include?(verb)
            {
              name: 'request_type',
              default: 'json',
              sticky: true,
              extends_schema: true,
              control_type: 'select',
              pick_list: [
                ['JSON request body', 'json'],
                ['URL encoded form', 'url_encoded_form'],
                ['Mutipart form', 'multipart'],
                ['Raw request body', 'raw']
              ]
            }
          end,
          {
            name: 'response_type',
            default: 'json',
            sticky: false,
            extends_schema: true,
            control_type: 'select',
            pick_list: [['JSON response', 'json'], ['Raw response', 'raw']]
          },
          if %w[get options delete].include?(verb)
            {
              name: 'input',
              label: 'Request URL parameters',
              sticky: true,
              add_field_label: 'Add URL parameter',
              control_type: 'form-schema-builder',
              type: 'object',
              properties: [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true
                },
                input_data
              ].compact
            }
          else
            {
              name: 'input',
              label: 'Request body parameters',
              sticky: true,
              type: 'object',
              properties:
                if config_fields['request_type'] == 'raw'
                  [{
                    name: 'data',
                    sticky: true,
                    control_type: 'text-area',
                    type: 'string'
                  }]
                else
                  [
                    {
                      name: 'schema',
                      sticky: input_schema.blank?,
                      extends_schema: true,
                      schema_neutral: true,
                      control_type: 'schema-designer',
                      sample_data_type: 'json_input',
                      custom_properties:
                        if config_fields['request_type'] == 'multipart'
                          [{
                            name: 'binary_content',
                            label: 'File attachment',
                            default: false,
                            optional: true,
                            sticky: true,
                            render_input: 'boolean_conversion',
                            parse_output: 'boolean_conversion',
                            control_type: 'checkbox',
                            type: 'boolean'
                          }]
                        end
                    },
                    input_data
                  ].compact
                end
            }
          end,
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require headers?',
            empty_list_text: 'Refer to the API documentation and add ' \
                             'required headers to this HTTP request',
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          }
        ].compact
      end
    },

    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
          elsif (output = config_fields['output'])
            output_schema = call('format_schema', parse_json(output))
            if output_schema.dig(0, 'type') == 'array' &&
               output_schema.dig(0, 'details', 'fake_array')
              response_body[:type] = 'array'
              response_body[:properties] = output_schema.dig(0, 'properties')
            else
              response_body[:type] = 'object'
              response_body[:properties] = output_schema
            end

            response_body
          end,
          if (headers = config_fields['response_headers'])
            header_props = parse_json(headers)&.map do |field|
              if field[:name].present?
                field[:name] = field[:name].gsub(/\W/, '_').downcase
              elsif field['name'].present?
                field['name'] = field['name'].gsub(/\W/, '_').downcase
              end
              field
            end

            { name: 'headers', type: 'object', properties: header_props }
          end
        ].compact
      end
    },
    search_object_input: {
      fields: lambda do |_connection, config_fields|
        schema = if config_fields['object'] == 'work_item'
                   call("#{config_fields['object']}_search_input", config_fields)
                 else
                   call("#{config_fields['object']}_search_input")
                 end

        call('format_schema', parse_json(schema.to_json))
      end
    },

    search_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = [{ name: 'value', label: config_fields['object'].pluralize.labelize,
                    type: 'array', of: 'object',
                    properties: call("#{config_fields['object']}_schema", config_fields) },
                  { name: 'count', type: 'integer' }]

        call('format_schema', parse_json(schema.to_json))
      end
    },

    get_object_input: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = case config_fields['object']
                 when 'project'
                   [{ name: 'id',
                      label: 'Project ID',
                      optional: false }]
                 when 'board'
                   [
                     { name: 'project', optional: false,
                       control_type: 'select',
                       extends_schema: true,
                       pick_list: 'projects',
                       toggle_hint: 'Select from list',
                       toggle_field: {
                         name: 'project', label: 'Project',
                         type: 'string', control_type: 'text',
                         extends_schema: true, change_on_blur: true,
                         optional: false,
                         toggle_hint: 'Enter custom value',
                         hint: 'Enter project name'
                       } },
                     { name: 'id',
                       label: 'Board ID',
                       optional: false }
                   ]
                 else
                   call("#{config_fields['object']}_get_input")
                 end

        call('format_schema', parse_json(schema.to_json))
      end
    },

    get_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = if config_fields['object'] == 'build_log'
                   [{ name: 'value', label: 'Build log' }, { name: 'count' }]
                 else
                   call("#{config_fields['object']}_schema", config_fields)
                 end

        call('format_schema', schema)
      end
    },

    create_object_input: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = call("#{config_fields['object']}_create_input", config_fields, 'create')
        call('format_schema', parse_json(schema.to_json))
      end
    },

    create_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = call("#{config_fields['object']}_schema", config_fields)
        call('format_schema', parse_json(schema.to_json))
      end
    },

    update_object_input: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = [{ name: 'id', optional: false,
                    label: "#{config_fields['object'].labelize} ID" }].
                 concat(call("#{config_fields['object']}_create_input", config_fields, 'update'))

        call('format_schema', parse_json(schema.to_json))
      end
    },

    update_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        schema = call("#{config_fields['object']}_schema", config_fields)
        call('format_schema', parse_json(schema.to_json))
      end
    },

    trigger_object_output: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        event_name = config_fields['event_type'].gsub(/[.-]/, '_')
        event_schema =
          if %w[build_completed ms_vss_release_release_created_event
                ms_vss_release_release_abandoned_event
                ms_vss_release_deployment_approval_completed_event
                ms_vss_release_deployment_approval_pending_event
                ms_vss_release_deployment_completed_event
                ms_vss_release_deployment_started_event
                ms_vss_pipelines_run_state_changed_event
                ms_vss_pipelines_stage_state_changed_event
                ms_vss_pipelinechecks_events_approval_pending
                ms_vss_pipelinechecks_events_approval_completed
                tfvc_checkin git_push git_pullrequest_created
                git_pullrequest_merged git_pullrequest_updated
                workitem_commented workitem_created workitem_deleted
                workitem_restored workitem_updated].include?(event_name)
            call("#{event_name}_schema")
          else
            [
              { name: 'id' },
              { name: 'name' },
              { name: 'fields' },
              { name: 'uri', label: 'URI' },
              { name: 'url', label: 'URL' }
            ]
          end

        schema = [{ name: 'id' },
                  { name: 'eventType' },
                  { name: 'publisherId' },
                  { name: 'scope' },
                  { name: 'message', type: 'object',
                    properties: [
                      { name: 'text' },
                      { name: 'html' },
                      { name: 'markdown' }
                    ] },
                  { name: 'detailedMessage', type: 'object',
                    properties: [
                      { name: 'text' },
                      { name: 'html' },
                      { name: 'markdown' }
                    ] },
                  { name: 'resource', type: 'object',
                    properties: event_schema },
                  { name: 'resourceVersion' },
                  { name: 'resourceContainers', type: 'object',
                    properties: [
                      { name: 'collection', type: 'object',
                        properties: [{ name: 'id' }] },
                      { name: 'account', type: 'object',
                        properties: [{ name: 'id' }] },
                      { name: 'project', type: 'object',
                        properties: [{ name: 'id' }] }
                    ] },
                  { name: 'createdDate', type: 'date_time' }]

        call('format_schema', parse_json(schema.to_json))
      end
    },

    upload_attachment_input: {
      fields: lambda do |_connection, _config_fields|
        [
          { name: 'project',
            control_type: 'select',
            optional: false,
            pick_list: 'projects',
            extends_schema: true,
            toggle_hint: 'Select from list',
            toggle_field: {
              toggle_hint: 'Enter custom value',
              name: 'project',
              type: 'string',
              control_type: 'text',
              extends_schema: true, change_on_blur: false,
              label: 'Project',
              optional: false,
              hint: 'Enter project name'
            } },
          { name: 'id', optional: false, label: 'Work item ID' },
          { name: 'fileName', optional: false,
            hint: 'Provide the file name with extention if needed. ' \
                  'e.g. <b>image.jpg</b>' },
          { name: 'content', optional: false,
            hint: 'Binary file content or text file. Max size: 130MB' },
          { name: 'comments', sticky: true,
            hint: 'Description of the attachment.' },
          { name: 'custom_fields',
            label: 'Work item output fields',
            sticky: true,
            extends_schema: true,
            schema_neutral: true,
            hint: 'Provide a sample JSON to include work item custom fields.',
            control_type: 'schema-designer',
            sample_data_type: 'json_input' }
        ]
      end
    },

    upload_attachment_output: {
      fields: lambda do |_connection, config_fields|
        schema = call('work_item_schema', config_fields)

        call('format_schema', parse_json(schema.to_json))
      end
    },

    workitem_created_updated_trigger_output: {
      fields: lambda do |_connection|
        schema = call('workitem_created_updated_trigger_schema')
        call('format_schema', parse_json(schema.to_json))
      end
    }
  },

  actions: {
    custom_action: {
      subtitle: 'Build your own Azure DevOps action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
          "#{object_value[:action_name] || 'Custom action'}</span> in " \
          "<span class='provider'>Azure DevOps</span>"
      end,

      help: {
        body: 'Build your own Azure Devops action with a HTTP request. ' \
              'The request will be authorized with your Azure DevOps connection.',
        learn_more_url: 'https://docs.microsoft.com/en-us/rest/api/azure/devops/?' \
                        'view=azure-devops-rest-7.1',
        learn_more_text: 'Azure DevOps API documentation'
      },

      config_fields: [
        {
          name: 'action_name',
          hint: "Give this action you're building a descriptive name, e.g. " \
                'create record, get record',
          default: 'Custom action',
          optional: false,
          schema_neutral: true
        },
        {
          name: 'verb',
          label: 'Method',
          hint: 'Select HTTP method of the request',
          optional: false,
          control_type: 'select',
          pick_list: %w[get post put patch options delete].map { |verb| [verb.upcase, verb] }
        }
      ],

      input_fields: lambda do |object_definition|
        object_definition['custom_action_input']
      end,

      execute: lambda do |_connection, input|
        verb = input['verb']
        if %w[get post put patch options delete].exclude?(verb)
          error("#{verb.upcase} not supported")
        end
        path = input['path']
        data = input.dig('input', 'data') || {}
        if input['request_type'] == 'multipart'
          data = data.each_with_object({}) do |(key, val), hash|
            hash[key] = if val.is_a?(Hash)
                          [val[:file_content], val[:content_type], val[:original_filename]]
                        else
                          val
                        end
          end
        end

        data = call('format_payload', data)

        request_headers = input['request_headers']&.
                          each_with_object({}) do |item, hash|
          hash[item['key']] = item['value']
        end || {}
        request = case verb
                  when 'get'
                    get(path, data)
                  when 'post'
                    if input['request_type'] == 'raw'
                      post(path).request_body(data)
                    else
                      post(path, data)
                    end
                  when 'put'
                    if input['request_type'] == 'raw'
                      put(path).request_body(data)
                    else
                      put(path, data)
                    end
                  when 'patch'
                    if input['request_type'] == 'raw'
                      patch(path).request_body(data)
                    else
                      patch(path, data)
                    end
                  when 'options'
                    options(path, data)
                  when 'delete'
                    delete(path, data)
                  end.case_sensitive_headers(request_headers)
        request = case input['request_type']
                  when 'url_encoded_form'
                    request.request_format_www_form_urlencoded
                  when 'multipart'
                    request.request_format_multipart_form
                  else
                    request
                  end
        response =
          if input['response_type'] == 'raw'
            request.response_format_raw
          else
            request
          end.
          after_error_response(/.*/) do |code, body, headers, message|
            error({ code: code, message: message, body: body, headers: headers }.
              to_json)
          end

        response.after_response do |_code, res_body, res_headers|
          {
            body: res_body ? call('format_response', res_body) : nil,
            headers: res_headers
          }
        end
      end,

      output_fields: lambda do |object_definition|
        object_definition['custom_action_output']
      end
    },
    search_records: {
      title: 'Search records',
      subtitle: 'Search records, e.g. builds, in Azure DevOps',
      description: lambda do |_connection, search_object_list|
        "Search <span class='provider'>" \
          "#{search_object_list[:object]&.pluralize || 'records'}</span> " \
          'in <span class="provider">Azure DevOps</span>'
      end,

      help: 'Returns all records that matches your search criteria.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :search_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['search_object_input']
      end,

      execute: lambda do |_connection, input|
        input['team'] = input['team'].encode_url if input['object'] == 'board'

        params = call('format_payload', input.except('object'))

        response = get(call('get_url', input), params).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        if input['object'] == 'work_item'
          response = { value: response['value']&.map do |record|
            { 'System.Id' => record&.[]('id'),
              'url' => record&.[]('url') }.
              merge(record&.[]('fields'))
          end || [] }
        end

        call('format_response', parse_json(response.to_json))
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['search_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), { '$top' => 1 })
      end
    },

    get_record: {
      title: 'Get record',
      subtitle: 'Get record, e.g. build, in Azure DevOps',
      description: lambda do |_connection, get_object_list|
        "Get <span class='provider'>" \
          "#{get_object_list[:object] || 'record'}</span> " \
          'in <span class="provider">Azure DevOps</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :get_object_list,
          hint: 'Select the object from list.'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['get_object_input']
      end,

      execute: lambda do |_connection, input|
        response = get("#{call('get_url', input)}/#{input.delete('id')}",
                       input.except('object', 'custom_fields')).
                   after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end
        if input['object'] == 'build_log'
          response['value'] = response['value']&.join("\n")
        elsif input['object'] == 'work_item'
          response = response&.[]('fields')&.
                     merge('System.Id' => response&.[]('id'),
                           'url' => response&.[]('url'))
        end
        call('format_response', parse_json(response.to_json))
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['get_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), { '$top' => 1 })
      end
    },

    create_record: {
      title: 'Create record',
      subtitle: 'Create record, e.g. build, in Azure DevOps',
      description: lambda do |_connection, create_object_list|
        "Create <span class='provider'>" \
          "#{create_object_list[:object] || 'record'}</span> " \
          'in <span class="provider">Azure DevOps</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :create_object_list,
          hint: 'Select the object from list.'
        },
        { name: 'project',
          control_type: 'select',
          optional: false,
          ngIf: "input.object == 'work_item'",
          pick_list: 'projects',
          extends_schema: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'project',
            type: 'string',
            control_type: 'text',
            extends_schema: true,
            label: 'Project',
            optional: false,
            hint: 'Enter project ID or project name. <b>It is required to manually specify the ' \
                  'work item fields if this field contains a dynamic value.</b>'
          } }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input']
      end,

      execute: lambda do |_connection, input|
        type = if input['type'].include?('~')
                 "$#{input['type'].split('~').last}"
               else
                 input['type']
               end

        url = call('get_url', input)
        payload = if input['object'] == 'work_item'
                    url = "#{url}/#{type}"
                    input.except('object', 'project', 'type', 'custom_fields').
                      map do |key, value|
                        {
                          op: 'add',
                          path: "/fields/#{key.gsub('__2e__', '.')}",
                          value: value
                        }
                      end
                  else
                    input.except('object')
                  end

        response = post(url).params('$expand': 'all').
                   request_body(payload.to_json).
                   headers('Content-Type': 'application/json-patch+json').
                   after_error_response(/.*/) do |_code, body, _headers, message|
                     error("#{message}: #{body}")
                   end
        if input['object'] == 'work_item'
          response = response&.[]('fields')&.merge('url' => response&.[]('url'))
        end
        call('format_response', response)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), { '$top' => 1 }).dig('value', 0)
      end
    },

    update_record: {
      title: 'Update record',
      subtitle: 'Update record, e.g. build, in Azure DevOps',
      description: lambda do |_connection, update_object_list|
        "Update <span class='provider'>" \
          "#{update_object_list[:object] || 'record'}</span> " \
          'in <span class="provider">Azure DevOps</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :update_object_list,
          hint: 'Select the object from list.'
        },
        { name: 'project',
          control_type: 'select',
          optional: false,
          ngIf: "input.object == 'work_item'",
          pick_list: 'projects',
          extends_schema: true,
          toggle_hint: 'Select from list',
          toggle_field: {
            toggle_hint: 'Enter custom value',
            name: 'project',
            type: 'string',
            control_type: 'text',
            extends_schema: true,
            label: 'Project',
            optional: false,
            hint: 'Enter project ID or project name. <b>It is required to manually specify the ' \
                  'work item fields if this field contains a dynamic value.</b>'
          } }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['update_object_input']
      end,

      execute: lambda do |_connection, input|
        url = "#{call('get_url', input)}/#{input.delete('id')}"
        payload = if input['object'] == 'work_item'
                    input.except('object', 'project', 'type', 'custom_fields').
                      map do |key, value|
                        if key == 'type'
                          {
                            op: 'add',
                            path: '/fields/System.WorkItemType',
                            value: value.split('~').first
                          }
                        else
                          {
                            op: 'add',
                            path: "/fields/#{key.gsub('__2e__', '.')}",
                            value: value
                          }
                        end
                      end
                  else
                    input.except('object')
                  end

        response = patch(url).params('$expand': 'all').
                   request_body(payload.to_json).
                   headers('Content-Type': 'application/json-patch+json').
                   after_error_response(/.*/) do |_code, body, _headers, message|
                     error("#{message}: #{body}")
                   end
        if input['object'] == 'work_item'
          response = response&.[]('fields')&.merge('url' => response&.[]('url'))
        end

        call('format_response', response)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['update_object_output']
      end,

      sample_output: lambda do |_connection, input|
        get(call('get_url', input), { '$top' => 1 }).dig('value', 0)
      end
    },

    upload_work_item_attachment: {
      title: 'Upload work item attachment',
      subtitle: 'Upload work item attachment in Azure DevOps',
      description: "Upload <span class='provider'>work item attachment" \
                   "</span> in <span class='provider'>Azure DevOps</span>",

      help: 'Attachment size should be less than 130MB.',

      input_fields: lambda do |object_definitions|
        object_definitions['upload_attachment_input']
      end,
      execute: lambda do |connection, input|
        file = post("/#{connection['organization']}/" \
                    "#{input['project'].encode_url}/_apis/wit/attachments").
               params(uploadType: 'Simple', fileName: input['fileName']).
               headers('Content-Type': 'application/octet-stream').request_body(input['content']).
               after_error_response(/.*/) do |_code, body, _header, message|
                 error("#{message}: #{body}")
               end
        payload = [
          {
            op: 'add',
            path: '/relations/-',
            value: {
              rel: 'AttachedFile',
              url: file&.[]('url'),
              attributes: {
                comment: input['comments']
              }
            }
          }
        ]
        response = patch("/#{connection['organization']}/" \
                         "#{input['project'].encode_url}/_apis/wit/workitems/#{input['id']}").
                   params('$expand': 'all').
                   headers('Content-Type': 'application/json-patch+json').
                   request_body(payload.to_json).
                   after_error_response(/.*/) do |_code, body, _headers, message|
                     error("#{message}: #{body}")
                   end
        response = response&.[]('fields')&.
                   merge({ 'url' => response&.[]('url'), 'attachment' => file })
        call('format_response', response)
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['upload_attachment_output'].push(
          { name: 'attachment', type: 'object',
            properties: [
              { name: 'id', label: 'Attachment ID' },
              { name: 'url', label: 'Attachment URL' }
            ] }
        )
      end
    }
  },

  triggers: {
    new_event: {
      title: 'New event',
      subtitle: 'Triggers immediately when an event occurs in Azure DevOps.',
      description: lambda do |_input, trigger_event_list|
        "New <span class='provider'>" \
          "#{trigger_event_list[:event_type]&.+(' ')}</span>event " \
          'in <span class="provider">Azure DevOps</span>'
      end,

      help: 'Triggered when an event is occured e.g. When build is completed.',

      config_fields: [
        {
          name: 'event_publisher',
          optional: false,
          control_type: 'select',
          pick_list: :event_publishers,
          hint: 'Select the event publisher from list.',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'event_publisher', label: 'Event publisher',
            type: 'string', control_type: 'text',
            optional: false, change_on_blur: true,
            toggle_hint: 'Enter custom value',
            hint: 'Enter publisher ID. E.g. tfs'
          }
        },
        {
          name: 'event_type', label: 'Event type',
          control_type: 'select', optional: false,
          pick_list: 'event_types',
          pick_list_params: { event_publishers: 'event_publisher' },
          hint: 'Select the event type from list.',
          toggle_hint: 'Select from list',
          toggle_field: {
            name: 'event_type', label: 'Event ID',
            type: 'string', control_type: 'text',
            optional: false, change_on_blur: true,
            toggle_hint: 'Enter custom value',
            hint: 'Enter event ID. E.g. workitem.created'
          }
        }
      ],

      input_fields: lambda do |_object_definitions|
        [
          { name: 'project', optional: false,
            control_type: 'select',
            pick_list: 'project_id_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'project', label: 'Project ID',
              type: 'string', control_type: 'text',
              optional: false,
              toggle_hint: 'Enter custom value',
              hint: 'Enter project ID'
            } }
        ]
      end,

      webhook_subscribe: lambda do |webhook_url, _connection, input|
        payload = {
          publisherId: input['event_publisher'],
          eventType: input['event_type'],
          resourceVersion: '1.0',
          consumerId: 'webHooks',
          consumerActionId: 'httpRequest',
          publisherInputs: { projectId: input['project'] },
          consumerInputs: { url: webhook_url }
        }

        post('_apis/hooks/subscriptions', payload).
          after_error_response(/.*/) do |_, body, _, message|
            error("#{message}: #{body}")
          end
      end,

      webhook_notification: lambda do |input, payload|
        if input['event_type'] == payload['eventType']
          if payload['eventType'].include?('workitem')
            if payload.dig('resource', 'fields').present?
              payload['resource']['fields'] =
                payload.dig('resource', 'fields').
                each_with_object({}) do |(key, val), hash|
                  key = key.to_s.gsub(/[.-]/, '_').gsub(' ', '_')
                  hash[key] = val
                end
            end
            if payload.dig('resource', 'revision', 'fields').present?
              payload['resource']['revision']['fields'] =
                payload.dig('resource', 'revision', 'fields').
                each_with_object({}) do |(key, val), hash|
                  key = key.to_s.gsub(/[.-]/, '_').gsub(' ', '_')
                  hash[key] = val
                end
            end
          end
          payload
        end
      end,

      webhook_unsubscribe: lambda do |webhook|
        delete("_apis/hooks/subscriptions/#{webhook['id']}").
          after_error_response(/.*/) do |_code, body, _header, message|
            error("#{message}: #{body}")
          end
      end,

      dedup: lambda do |item|
        item['id']
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['trigger_object_output']
      end
    },
    new_work_item: {
      title: 'New work item',
      subtitle: 'Triggers when one or more work items are created in Azure DevOps',
      batch: true,
      description: lambda do |_input|
                     "Retrieves newly created <span class='provider'>work items</span> in " \
                       "<span class='provider'>Azure DevOps</span>."
                   end,
      help: 'The trigger will periodically check for new work items ' \
            'based on the polling interval.',

      config_fields: [
        {
          name: 'batch_size',
          control_type: 'integer',
          label: 'Batch size',
          default: 100,
          hint: 'Defaults to 100 if not specified, with a maximum limit of 200.'
        }
      ],
      input_fields: lambda do |_object_definitions|
                      [
                        { name: 'since',
                          label: 'When first started, this recipe should pick up events from',
                          hint: 'When you start recipe for the first time, ' \
                                'it picks up work items from this specified date and time. ' \
                                'Leave empty to get work items created within the past hour.',
                          sticky: true,
                          type: 'timestamp' },
                        {
                          name: 'project',
                          optional: false,
                          control_type: 'select',
                          pick_list: 'projects',
                          toggle_hint: 'Select from list',
                          toggle_field: {
                            name: 'project',
                            label: 'Project name',
                            type: 'string',
                            control_type: 'text',
                            optional: false,
                            toggle_hint: 'Enter custom value',
                            hint: 'Enter project name'
                          }
                        }
                      ]
                    end,

      poll: lambda do |connection, input, closure|
              closure ||= {}
              created_after = (closure['created_after'] ||
                input['since'] ||
                1.hour.ago).to_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%2N')
              batch_size = (input['batch_size'] || 100).to_i.clamp(1, 200)

              query = 'SELECT [System.Id] ' \
                      'FROM WorkItems WHERE ' \
                      "[System.TeamProject] = '#{input['project']}' " \
                      "AND [System.CreatedDate] >= '#{created_after}' " \
                      'ORDER BY [System.CreatedDate] ASC'

              response = post("https://dev.azure.com/#{connection['organization']}/" \
                              "#{input['project']}/_apis/wit/wiql?api-version=" \
                              "#{connection['api_version']}&timePrecision=true&$top=#{batch_size}").
                         payload(query: query).
                         after_error_response(/.*/) do |_, body, _, message|
                error("#{message}: #{body}")
              end

              work_item_ids = response['workItems']&.map { |item| item['id'] } || []
              if work_item_ids.empty?
                closure = { created_after: created_after }
                return { events: [], next_poll: closure, can_poll_more: false }
              end

              bulk_response = get(
                "https://dev.azure.com/#{connection['organization']}/" \
                "#{input['project']}/_apis/wit/workitems?" \
                "ids=#{work_item_ids.join(',')}&api-version=#{connection['api_version']}"
              ).after_error_response(/.*/) do |_, body, _, message|
                error("#{message}: #{body}")
              end
              work_items = bulk_response['value']

              if work_items.any?
                last_created_date_time =
                  (Time.parse(work_items.last.dig('fields', 'System.CreatedDate')) + 0.01).
                  utc.strftime('%Y-%m-%dT%H:%M:%S.%2NZ')
              end
              closure = { created_after: last_created_date_time }
              {
                events: [{ work_items: call('format_response', parse_json(work_items.to_json)) }],
                next_poll: closure,
                can_poll_more: work_items.size == batch_size
              }
            end,
      dedup: lambda do |_work_items|
               Time.now.to_f
             end,

      output_fields: lambda do |object_definitions|
                       [
                         {
                           name: 'work_items',
                           type: 'array',
                           of: 'object',
                           properties: object_definitions['workitem_created_updated_trigger_output']
                         }
                       ]
                     end,

      sample_output: lambda do |_connection, _input|
                       call('sample_created_updated_workitem_trigger_output')
                     end
    },
    updated_work_item: {
      title: 'New/Updated work item',
      subtitle: 'Triggers when one or more work items are created or updated in Azure DevOps',
      batch: true,
      description: lambda do |_input|
        "Retrieves newly created and updated <span class='provider'>work items</span> in " \
          "<span class='provider'>Azure DevOps</span>."
      end,
      help: 'The trigger will periodically check for new and updated work items ' \
            'based on the polling interval.',
      config_fields: [
        {
          name: 'batch_size',
          control_type: 'integer',
          label: 'Batch size',
          default: 100,
          hint: 'Defaults to 100 if not specified, with a maximum limit of 200.'
        }
      ],
      input_fields: lambda do |_object_definitions|
                      [
                        { name: 'since',
                          label: 'When first started, this recipe should pick up events from',
                          hint: 'When you start recipe for the first time, ' \
                                'it picks up work items from this specified date and time. ' \
                                'Leave empty to get work items created or ' \
                                'updated within the past hour.',
                          sticky: true,
                          type: 'timestamp' },
                        {
                          name: 'project',
                          optional: false,
                          control_type: 'select',
                          pick_list: 'projects',
                          toggle_hint: 'Select from list',
                          toggle_field: {
                            name: 'project',
                            label: 'Project name',
                            type: 'string',
                            control_type: 'text',
                            optional: false,
                            toggle_hint: 'Enter custom value',
                            hint: 'Enter project name'
                          }
                        }
                      ]
                    end,

      poll: lambda do |connection, input, closure|
              closure ||= {}
              updated_after = (closure['updated_after'] ||
                 input['since'] ||
                1.hour.ago).to_time.utc.strftime('%Y-%m-%dT%H:%M:%S.%2NZ')

              batch_size = (input['batch_size'] || 100).to_i.clamp(1, 200)

              query = 'SELECT [System.Id] ' \
                      'FROM WorkItems WHERE ' \
                      "[System.TeamProject] = '#{input['project']}' " \
                      "AND [System.ChangedDate] >= '#{updated_after}' " \
                      'ORDER BY [System.ChangedDate] ASC'

              response = post(
                "https://dev.azure.com/#{connection['organization']}/" \
                "#{input['project']}/_apis/wit/wiql" \
                "?api-version=#{connection['api_version']}" \
                "&timePrecision=true&$top=#{batch_size}"
              ).payload(query: query).
                         after_error_response(/.*/) do |_, body, _, message|
                error("#{message}: #{body}")
              end
              work_item_ids = response['workItems']&.map { |item| item['id'] } || []
              if work_item_ids.empty?
                closure = { updated_after: updated_after }
                return { events: [], next_poll: closure, can_poll_more: false }
              end
              bulk_response = get(
                "https://dev.azure.com/#{connection['organization']}/" \
                "#{input['project']}/_apis/wit/workitems" \
                "?ids=#{work_item_ids.join(',')}" \
                "&api-version=#{connection['api_version']}"
              ).after_error_response(/.*/) do |_, body, _, message|
                error("#{message}: #{body}")
              end

              work_items = bulk_response['value']
              if work_items.any?
                last_updated_date_time =
                  (Time.parse(work_items.last.dig('fields', 'System.ChangedDate')) + 0.01).
                  utc.strftime('%Y-%m-%dT%H:%M:%S.%2NZ')
              end

              closure = { updated_after: last_updated_date_time }

              {
                events: [{ work_items: call('format_response', parse_json(work_items.to_json)) }],
                next_poll: closure,
                can_poll_more: work_items.size == batch_size
              }
            end,

      dedup: lambda do |_work_items|
               Time.now.to_f
             end,

      output_fields: lambda do |object_definitions|
                       [
                         {
                           name: 'work_items',
                           type: 'array',
                           of: 'object',
                           properties: object_definitions['workitem_created_updated_trigger_output']
                         }
                       ]
                     end,

      sample_output: lambda do |_connection, _input|
                       call('sample_created_updated_workitem_trigger_output')
                     end
    }

  },

  pick_lists: {
    search_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Board board],
        ['Board column', 'board_column'],
        %w[Build build],
        ['Build log', 'build_log'],
        %w[Run run],
        ['Work item', 'work_item']
      ]
    end,

    get_object_list: lambda do |_connection|
      [
        %w[Project project],
        %w[Board board],
        %w[Build build],
        ['Build log', 'build_log'],
        %w[Run run],
        ['Work item', 'work_item']
      ]
    end,

    create_object_list: lambda do |_connection|
      [
        ['Work item', 'work_item']
      ]
    end,

    update_object_list: lambda do |_connection|
      [
        ['Work item', 'work_item']
      ]
    end,

    trigger_object_list: lambda do |_connection|
      [
        %w[Opportunity opportunity]
      ]
    end,

    trigger_event_list: lambda do |_connection|
      [
        ['Interview deleted', 'interviewDeleted']
      ]
    end,

    projects: lambda do |_connection|
      get('_apis/projects').
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}.")
        end&.[]('value')&.pluck('name', 'name') || []
    end,

    project_id_list: lambda do |_connection|
      get('_apis/projects').
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('value')&.pluck('name', 'id') || []
    end,

    work_items: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      post('_apis/wit/wiql?$top=1000').
        payload(query: "SELECT * FROM workitems WHERE [System.TeamProject] = '#{project}'").
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('workItems')&.map { |item| [item['id'].to_s, item['id'].to_s] }
    end,

    pipelines: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      get("#{project.encode_url}/_apis/pipelines").
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('value')&.map { |item| [item['name'], item['id']] }
    end,

    event_publishers: lambda do |connection|
      get("/#{connection['organization']}/_apis/hooks/publishers").
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('value')&.pluck('name', 'id') || []
    end,

    event_types: lambda do |_connection, event_publishers:|
      has_datapill = event_publishers.include?("{_('data.") ||
                     event_publishers.include?('pill_type')
      next [] if event_publishers.blank? || has_datapill

      get("_apis/hooks/publishers/#{event_publishers}/eventtypes").
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('value')&.pluck('name', 'id') || []
    end,

    work_item_types_create: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      get("#{project.encode_url}/_apis/wit/workitemtypes").
        after_error_response(/.*/) do |_code, body, _headers, message|
          error("#{message}: #{body}")
        end&.[]('value')&.map { |val| [val['name'], "#{val['name']}~#{val['referenceName']}"] }
    end,

    area_paths: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      area = get("#{project.encode_url}/_apis/wit/classificationnodes/Areas?$depth=100")
      call('pick_list_with_children', 'area' => area, 'root_path' => '').
        map { |path| [path, path] }
    end,
    iteration_paths: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      area = get("#{project.encode_url}/_apis/wit/classificationnodes/Iterations?$depth=100")
      call('pick_list_with_children', 'area' => area, 'root_path' => '').
        map { |path| [path, path] }
    end,
    assigned_to: lambda do |_connection, project:|
      has_datapill = project.include?("{_('data.") || project.include?('pill_type')
      next [] if project.blank? || has_datapill

      members = []
      project_teams = get("_apis/projects/#{project.encode_url}/teams")&.[]('value')
      project_teams.map do |team|
        members << get("_apis/projects/#{project.encode_url}/teams/#{team['id']}/members")&.
          []('value')&.map { |member| member.dig('identity', 'displayName') }
      end
      members.flatten.uniq.compact.map { |member| [member, member] }
    end
  }
}
