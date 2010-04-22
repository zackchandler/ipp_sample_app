require 'rubygems'
require 'sinatra'
require 'base64'
require 'httparty'
require 'hpricot'
require 'ostruct'
require 'vendor/intuit_saml.rb'

# APP_DBID is your unique app id
# When running your app in workplace the APP_DBID is displayed in the URL field
# https://workplace.intuit.com/db/{APP_DBID}
APP_DBID = ENV['APP_DBID']

# From your app dashboard click Customize => Application => Advanced Settings
# to create an application token
APP_TOKEN = ENV['APP_TOKEN']

# Private key is needed to decrypt the SAML message
private_key = ENV['PRIVATE_KEY']

# we practice safe html escaping
helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

# IPP will post the SAML message to this endpoint when app is loaded in Workplace
post '/' do
  # Grab SAML message passed from IPP
  saml_response = params['SAMLResponse']
  
  # Decode SAML response and pass into Saml helper to decrypt
  saml = Intuit::Saml.new(:saml_xml => Base64.decode64(saml_response), :private_key => private_key)

  # use the IPP Web API call API_GetIDSRealm to find the realm which is required for IDS
  options = {
    :act => 'API_GetIAMRealm',
    :ticket => saml.ticket,
    :apptoken => APP_TOKEN
  }
  response = HTTParty.get("https://workplace.intuit.com/db/#{APP_DBID}?" + build_query(options))
  realm = Hpricot.XML(response.body).at('realm').inner_text

  # Setup the post to query customers from IDS
  body = '<CustomerQuery xmlns="http://www.intuit.com/sb/cdm/xmlrequest" />'
  auth_header = %(INTUITAUTH intuit-app-token="#{APP_TOKEN}",intuit-token="#{saml.ticket}")
  path = "https://services.intuit.com/sb/customer/v1/#{realm}"
  options = {
    :headers => { 'Authorization' => auth_header, 'Content-Type' =>'text/xml' },
    :body => body,
    :format => :donotparse
  }
  
  # Make call to IDS and receive the XML payload
  response = HTTParty.post(path, options)

  # Hpricot payload and pull out customer names for display
  doc = Hpricot.XML(response)
  @customers = []
  doc.search('Customer').each do |node|
    @customers << OpenStruct.new(:name => (node/'cmo:Name').inner_text)
  end
  
  # Display customer list in the Intuit Workplace iframe
  erb :index
end

__END__

@@ layout
<html>
  <body>
    <%= yield %>
  </body>
</html>

@@ index
<h1>Customers</h1>
<ul>
  <% for customer in @customers %>
    <li><%= h customer.name %></li>
  <% end %>
</ul>