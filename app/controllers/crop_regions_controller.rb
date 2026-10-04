class CropRegionsController < ApplicationController
  def image
    region = CropRegion.find(params[:id])
    expires_in 1.hour, public: false
    send_data ImageStorage.read(region.r2_key), type: "image/jpeg", disposition: "inline"
  end
end
