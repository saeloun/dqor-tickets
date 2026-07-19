Razorpay.setup(ENV["RAZORPAY_KEY_ID"], ENV["RAZORPAY_KEY_SECRET"])
Razorpay::Request.open_timeout 5
Razorpay::Request.read_timeout 15
