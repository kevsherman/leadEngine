abort "Demo seeds are development-only" unless Rails.env.development? || Rails.env.test?
Operator.find_or_create_by!(email: ENV.fetch("OPERATOR_EMAIL", "kevin@example.test")) do |operator|
  operator.password = ENV.fetch("OPERATOR_PASSWORD", "local-demo-password")
end
examples = [
  { id: "courtyard", name: "Morgan Chen", email: "morgan@example.test", subject: "Breeze blocks for our courtyard", project: "Vancouver courtyard", category: "Quote request", language: "English", age: 6.hours,
    known: { location: "Vancouver, BC", pattern: "Clover, white", quantity: "80 large blocks", delivery: "Requested" }, missing: [ "Full delivery address", "Residential or commercial site", "Unloading equipment and access" ],
    body: "Hi Kevin,\n\nWe are planning a courtyard screen in Vancouver and would love to use 80 large white Clover blocks. Could you put together a quote with delivery?\n\nThanks,\nMorgan",
    reply: "Hi Morgan,\n\nThanks for getting in touch about your courtyard project. To prepare a delivered quote for 80 large white Clover blocks, could you share the full delivery address, confirm whether the site is residential or commercial, and let us know if unloading equipment is available or there are any access restrictions?\n\nWe will confirm pricing and availability as we prepare the quote.\n\nBest,\nKevin\nBreeze Block Canada" },
  { id: "studio", name: "Alex Rivera", email: "alex@example.test", subject: "A screen wall for our new studio", project: "Victoria studio", category: "New sales inquiry", language: "English", age: 3.hours,
    known: { location: "Victoria, BC", area: "Approximately 45 sq ft", customer_type: "Design studio" }, missing: [ "Preferred pattern, size and colour", "Delivery or pickup" ],
    body: "Hello! We're a design studio fitting out a space in Victoria. We need around 45 square feet of breeze blocks for a divider. Could you help us choose a pattern? We haven't decided on a colour yet.\n\nAlex",
    reply: "Hi Alex,\n\nThank you for your interest in a breeze block divider for your studio. Do you have a preferred pattern, block size or colour? Please also let us know whether you are considering pickup or delivery.\n\nWe can use those details to work out the block count and the next steps for your project.\n\nBest,\nKevin\nBreeze Block Canada" },
  { id: "samples", name: "Camille Roy", email: "camille@example.test", subject: "Échantillons pour un projet à Montréal", project: "Montréal rénovation", category: "Samples", language: "French", age: 1.hour,
    known: { location: "Montréal, QC", request: "Samples", language: "French" }, missing: [ "Modèles et couleurs souhaités", "Adresse de livraison" ],
    body: "Bonjour,\n\nNous préparons une rénovation à Montréal. Est-il possible de commander des échantillons pour choisir un modèle et une couleur?\n\nMerci,\nCamille",
    reply: "Bonjour Camille,\n\nMerci pour votre intérêt. Quels modèles et couleurs souhaitez-vous examiner? Pour préparer les options d'échantillons et de livraison, pourriez-vous également nous transmettre votre adresse de livraison?\n\nNous confirmerons les prix et la disponibilité avant toute commande.\n\nCordialement,\nKevin\nBreeze Block Canada" }
]
examples.each do |example|
  Conversation.transaction do
    next if Conversation.exists?(source_id: "example-#{example[:id]}")
    conversation = Conversation.create!(source_id: "example-#{example[:id]}", customer_name: example[:name], customer_email: example[:email],
      subject: example[:subject], project: example[:project], category: example[:category], language: example[:language],
      next_action: "Review follow-up draft", known_fields: example[:known], missing_fields: example[:missing], last_activity_at: example[:age].ago)
    conversation.messages.create!(provider_id: "fake-inquiry-#{example[:id]}", direction: "inbound", sender: example[:email], recipient: "sales@breezeblock.ca",
      subject: example[:subject], body: example[:body], created_at: example[:age].ago)
    conversation.create_email_draft!(to: example[:email], subject: "Re: #{example[:subject]}", body: example[:reply])
    conversation.audit_events.create!(action: "example_inquiry_imported")
  end
end
puts "Demo ready: #{Conversation.count} conversations. Login: #{ENV.fetch('OPERATOR_EMAIL', 'kevin@example.test')}"
