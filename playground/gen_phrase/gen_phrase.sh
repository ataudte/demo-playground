#!/bin/bash
# arrays for different parts of speech
adjectives=("Innovative" "Disruptive" "Agile" "Scalable" "Strategic" "Synergistic" "Seamless" "Cutting-edge" "Transformative" "Dynamic" "Game-changing" "Data-driven" "Collaborative" "Holistic" "Progressive" "Customer-centric" "Proactive" "Global" "Sustainable" "Digital")
nouns=("Synergy" "Innovation" "Disruption" "Paradigm" "Optimization" "Agility" "Transformation" "Growth" "Empowerment" "Collaboration" "Sustainability" "Integration" "Strategy" "Execution" "Efficiency" "Engagement" "Digitalization" "Customer-Centricity" "Leadership" "Impact")
verbs=("leverages" "optimizes" "synergizes" "disrupts" "empowers" "innovates" "streamlines" "catalyzes" "maximizes" "accelerates" "transforms" "engages" "drives" "scales" "monetizes" "pivots" "iterates" "gamifies" "integrates" "revolutionizes")
adverbs=("strategically" "efficiently" "effectively" "proactively" "seamlessly" "synergistically" "innovatively" "disruptively" "dynamically" "holistically" "authentically" "collaboratively" "agilely" "globally" "digitally" "sustainably" "rapidly" "creatively" "optimaly" "empoweringly")
# random phrases
for i in {1..10}; do
  noun=${nouns[$RANDOM % ${#nouns[@]}]}
  verb=${verbs[$RANDOM % ${#verbs[@]}]}
  adjective=${adjectives[$RANDOM % ${#adjectives[@]}]}
  adverb=${adverbs[$RANDOM % ${#adverbs[@]}]}
  # print phrase
  echo "$adjective $noun $verb $adverb."
done
