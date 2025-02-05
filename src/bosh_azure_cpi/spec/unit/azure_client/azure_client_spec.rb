# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

describe Bosh::AzureCloud::AzureClient do
  let(:logger) { Bosh::Clouds::Config.logger }
  let(:azure_client) do
    Bosh::AzureCloud::AzureClient.new(
      mock_azure_config,
      logger
    )
  end
  let(:subscription_id) { mock_azure_config.subscription_id }
  let(:tenant_id) { mock_azure_config.tenant_id }
  let(:api_version) { AZURE_API_VERSION }
  let(:api_version_network) { AZURE_RESOURCE_PROVIDER_NETWORK }
  let(:default_resource_group) { mock_azure_config.resource_group_name }
  let(:resource_group) { 'fake-resource-group-name' }
  let(:request_id) { 'fake-request-id' }

  let(:token_uri) { "https://login.microsoftonline.com/#{tenant_id}/oauth2/token?api-version=#{api_version}" }
  let(:operation_status_link) { "https://management.azure.com/subscriptions/#{subscription_id}/operations/#{request_id}" }

  let(:vm_name) { 'fake-vm-name' }
  let(:valid_access_token) { 'valid-access-token' }
  let(:expires_on) { (Time.new + 1800).to_i.to_s }

  describe '#rest_api_url' do
    it 'returns the right url if all parameters are given' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      others = 'd'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               name: name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/c/d")
    end

    it 'returns the right url if resource group name is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      others = 'd'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               name: name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group}/providers/a/b/c/d")
    end

    it 'returns the right url if name is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      others = 'd'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               others: others
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/d")
    end

    it 'returns the right url if others is not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      name = 'c'
      resource_group_name = 'e'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type,
               resource_group_name: resource_group_name,
               name: name
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/e/providers/a/b/c")
    end

    it 'returns the right url if resource_group_name, name and others are all not provided' do
      resource_provider = 'a'
      resource_type = 'b'
      expect(azure_client.rest_api_url(
               resource_provider,
               resource_type
             )).to eq("/subscriptions/#{subscription_id}/resourceGroups/#{default_resource_group}/providers/a/b")
    end
  end

  describe '#_parse_name_from_id' do
    context 'when id is empty' do
      it 'should raise an error' do
        id = ''
        expect do
          azure_client.send(:_parse_name_from_id, id)
        end.to raise_error(/"#{id}" is not a valid URL./)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d'
      it 'should raise an error' do
        expect do
          azure_client.send(:_parse_name_from_id, id)
        end.to raise_error(/"#{id}" is not a valid URL./)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d/e' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d/e'
      it 'should return the name' do
        result = {}
        result[:subscription_id]     = 'a'
        result[:resource_group_name] = 'b'
        result[:provider_name]       = 'c'
        result[:resource_type]       = 'd'
        result[:resource_name]       = 'e'
        expect(azure_client.send(:_parse_name_from_id, id)).to eq(result)
      end
    end

    context 'when id is /subscriptions/a/resourceGroups/b/providers/c/d/e/f' do
      id = '/subscriptions/a/resourceGroups/b/providers/c/d/e/f'
      it 'should return the name' do
        result = {}
        result[:subscription_id]     = 'a'
        result[:resource_group_name] = 'b'
        result[:provider_name]       = 'c'
        result[:resource_type]       = 'd'
        result[:resource_name]       = 'e'
        expect(azure_client.send(:_parse_name_from_id, id)).to eq(result)
      end
    end
  end

  describe '#get_resource_by_id' do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}/foo/bar/foo" }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{api_version}" }
    let(:response_body) do
      {
        'id' => 'foo',
        'name' => 'name'
      }.to_json
    end

    context 'when token is valid, getting response succeeds' do
      context 'when no error happens' do
        it 'should return null if response body is null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).to be_nil
        end

        it 'should return the resource if response body is not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: response_body,
            headers: {}
          )
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).not_to be_nil
        end
      end
    end

    context 'when token is invalid' do
      it 'should raise an error if token is not gotten' do
        stub_request(:post, token_uri).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/get_token - http code: 404/)
      end

      it 'should raise an error if tenant_id, client_id or client_secret/certificate is invalid' do
        stub_request(:post, token_uri).to_return(
          status: 401,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error %r{get_token - http code: 401. Azure authentication failed: Invalid tenant_id, client_id or client_secret/certificate.}
      end

      it 'should raise an error if the request is invalid' do
        stub_request(:post, token_uri).to_return(
          status: 400,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error %r{get_token - http code: 400. Azure authentication failed: Bad request. Please assure no typo in values of tenant_id, client_id or client_secret/certificate.}
      end

      it 'should raise an error if authentication retry fails' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 401,
          body: '',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/Azure authentication failed: Token is invalid./)
      end
    end

    context 'when token expired' do
      context 'when authentication retry succeeds' do
        before do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return({
                                                       status: 401,
                                                       body: 'The token expired'
                                                     },
                                                     status: 200,
                                                     body: response_body,
                                                     headers: {})
        end

        it 'should return the resource' do
          expect(
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          ).not_to be_nil
        end
      end

      context 'when authentication retry fails' do
        before do
          stub_request(:post, token_uri).to_return({
                                                     status: 200,
                                                     body: {
                                                       'access_token' => valid_access_token,
                                                       'expires_on' => expires_on
                                                     }.to_json,
                                                     headers: {}
                                                   },
                                                   status: 401,
                                                   body: '',
                                                   headers: {})
          stub_request(:get, resource_uri).to_return(
            status: 401,
            body: 'The token expired'
          )
        end

        it 'should raise an error' do
          expect do
            azure_client.get_resource_by_id(url, 'api-version' => api_version)
          end.to raise_error %r{get_token - http code: 401. Azure authentication failed: Invalid tenant_id, client_id or client_secret/certificate.}
        end
      end
    end

    context 'when getting response fails' do
      it 'should return nil if Azure returns 204' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 204,
          body: '',
          headers: {}
        )

        expect(
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        ).to be_nil
      end

      it 'should return nil if Azure returns 404' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 404,
          body: '',
          headers: {}
        )

        expect(
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        ).to be_nil
      end

      it 'should raise an error if other status code returns' do
        stub_request(:post, token_uri).to_return(
          status: 200,
          body: {
            'access_token' => valid_access_token,
            'expires_on' => expires_on
          }.to_json,
          headers: {}
        )
        stub_request(:get, resource_uri).to_return(
          status: 400,
          body: '{"foo":"bar"}',
          headers: {}
        )

        expect do
          azure_client.get_resource_by_id(url, 'api-version' => api_version)
        end.to raise_error(/http_get - http code: 400. Error message: {"foo":"bar"}/)
      end
    end
  end

  describe '#get_resource_group' do
    let(:url) { "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group}" }
    let(:group_api_version) { AZURE_RESOURCE_PROVIDER_GROUP }
    let(:resource_uri) { "https://management.azure.com#{url}?api-version=#{group_api_version}" }
    let(:response_body) do
      {
        'id' => 'fake-id',
        'name' => 'fake-name',
        'location' => 'fake-location',
        'tags' => 'fake-tags',
        'properties' => {
          'provisioningState' => 'fake-state'
        }
      }.to_json
    end
    let(:fake_resource_group) do
      {
        id: 'fake-id',
        name: 'fake-name',
        location: 'fake-location',
        tags: 'fake-tags',
        provisioning_state: 'fake-state'
      }
    end

    context 'when token is valid' do
      context 'getting response succeeds' do
        it 'should return null if response body is null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: '',
            headers: {}
          )
          expect(
            azure_client.get_resource_group(resource_group)
          ).to be_nil
        end

        it 'should return the resource if response body is not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri).to_return(
            status: 200,
            body: response_body,
            headers: {}
          )
          expect(
            azure_client.get_resource_group(resource_group)
          ).to eq(fake_resource_group)
        end
      end

      context 'getting response fails for EOFError but retry returns 200' do
        it 'should return not null' do
          stub_request(:post, token_uri).to_return(
            status: 200,
            body: {
              'access_token' => valid_access_token,
              'expires_on' => expires_on
            }.to_json,
            headers: {}
          )
          stub_request(:get, resource_uri)
            .to_raise(EOFError.new).then
            .to_return(
              status: 200,
              body: response_body,
              headers: {}
            )

          expect(azure_client).to receive(:sleep).once
          expect(
            azure_client.get_resource_group(resource_group)
          ).to eq(fake_resource_group)
        end
      end
    end
  end
end
