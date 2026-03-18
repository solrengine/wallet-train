class Transfer < ApplicationRecord
  include Solrengine::Transactions::Transferable
end
