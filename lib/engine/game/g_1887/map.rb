# frozen_string_literal: true

module Engine
  module Game
    module G1887
      module Map
        LAYOUT = :pointy

        TILES = {
          '3' => 6,
          '4' => 6,
          '5' => 5,
          '6' => 5,
          '7' => 8,
          '8' => 16,
          '9' => 12,
          '14' => 3,
          '15' => 3,
          '16' => 1,
          '17' => 1,
          '18' => 1,
          '19' => 1,
          '20' => 1,
          '21' => 1,
          '22' => 1,
          '23' => 3,
          '24' => 3,
          '25' => 2,
          '26' => 2,
          '27' => 2,
          '28' => 1,
          '29' => 1,
          '30' => 1,
          '31' => 1,
          '39' => 1,
          '40' => 1,
          '41' => 1,
          '42' => 1,
          '43' => 1,
          '44' => 1,
          '45' => 2,
          '46' => 2,
          '47' => 2,
          '57' => 4,
          '58' => 4,
          '63' => 4,
          '70' => 2,
          '619' => 2,
          '624' => 1,
          '1' => 1,
          '55' => 1,
          '56' => 1,
          '69' => 1,
          '630' => 1,
          '632' => 1,
          # Not a site tile: your green '83|c' (same track as brown #42).
          '83c' => {
            'count' => 1,
            'color' => 'green',
            'code' => 'path=a:0,b:3;path=a:3,b:5;path=a:0,b:5',
          },
          # G1 and G2 (2 each, gray) are left out: they have no track definition yet.
        }.freeze

        LOCATION_NAMES = {
          'F16' => 'Buenos Aires',
          'F12' => 'Buenos Aires (Oeste)',
          'E9' => 'Rosario',
          'L8' => 'Bahia Blanca',
          'D16' => 'Santa Fe',
          'G19' => 'La Plata',
          'E5' => 'Mendoza',
          'C13' => 'Cordoba',
          'I13' => 'Rauch',
          'K11' => 'Benito Juarez',
          'N10' => 'Carmen de Patagones',
          'F26' => 'Entre Rios',
          'F28' => 'Montevideo',
          'A13' => 'Bolivia / Paraguay',
          'E3' => 'Andes / Chile',
          'F22' => 'Atlantic Export',
          'N12' => 'Patagonia',
          'G13' => 'Chascomus',
          'H16' => 'Las Flores',
          'I9' => 'Azul',
          'J12' => 'Tandil',
          'K13' => 'Tres Arroyos',
          'E15' => 'Campana',
          'D12' => 'Zarate',
          'D10' => 'Pergamino',
          'D14' => 'Galvez',
          'C11' => 'Rafaela',
          'F14' => 'Banfield',
          'F8' => 'Lujan',
          'J18' => 'Dolores',
          'H10' => 'Olavarria',
          'M11' => 'Viedma',
          'L14' => 'Bahia San Blas',
          'G15' => 'La Portena (1857)',
          'G5' => 'Chivilcoy',
          'G7' => 'San Luis',
          'F6' => 'Mercedes',
          'A11' => 'Salta',
          'B10' => 'Tucuman',
        }.freeze

        HEXES = {
          red: {
            ['F28'] => 'offboard=revenue:yellow_30|brown_70;path=a:0,b:_0',
            ['A13'] => 'offboard=revenue:yellow_20|brown_60;path=a:4,b:_0;path=a:5,b:_0',
            ['E3'] => 'offboard=revenue:yellow_20|brown_50;path=a:4,b:_0;path=a:5,b:_0',
            ['F22'] => 'offboard=revenue:yellow_40|brown_90;path=a:0,b:_0;path=a:4,b:_0',
            ['N12'] => 'offboard=revenue:yellow_10|brown_40;path=a:1,b:_0;path=a:3,b:_0',
          },
          gray: {
            ['G19'] => 'city=revenue:40;path=a:2,b:_0;path=a:5,b:_0',
            ['J18'] => 'town=revenue:30;path=a:2,b:_0',
          },
          white: {
            %w[A9 A15 B8 B12 B16 C9 C15 C17 E7 E11 E13 F10 F18 F20 G9 G11 G17 G23 G25 G27 H6 H8 H12 H14 H18 H22 H24 I7 I11 I15 I17 I19 I21 J8 J10 J16 K7 K9 K15 K17 L6 L10 L12 L16 M7 M9 M13 N8] => 'blank',
            %w[A11 B10 C13 D16 E5 E9 F26 G7 I13 K11 L8 N10] => 'city=revenue:0',
            %w[C11 D10 D14 E15 F6 F14 G5 G13 G15 H10 I9 L14 M11] => 'town=revenue:0',
            %w[F8 H16 J12] => 'town=revenue:0;town=revenue:0',
            %w[D4 F4] => 'upgrade=cost:40,terrain:mountain',
            %w[B14 D6 D8] => 'upgrade=cost:30,terrain:mountain',
            ['D18'] => 'upgrade=cost:30,terrain:water',
            ['E17'] => 'upgrade=cost:20,terrain:water',
            ['H20'] => 'upgrade=cost:40,terrain:swamp',
          },
          yellow: {
            ['F16'] => 'city=revenue:20;path=a:0,b:_0;path=a:3,b:_0;upgrade=cost:30,terrain:swamp',
            ['F12'] => 'city=revenue:20;path=a:2,b:_0;path=a:5,b:_0',
          },
          green: {
            ['K13'] => 'city=revenue:40,slots:2;path=a:2,b:_0;path=a:0,b:_0;path=a:1,b:_0;path=a:4,b:_0',
            ['D12'] => 'city=revenue:30,slots:2;path=a:2,b:_0;path=a:3,b:_0;path=a:1,b:_0;path=a:4,b:_0',
          },
          blue: {
            ['G21'] => 'path=a:3,b:5;path=a:2,b:4',
            ['F24'] => 'path=a:1,b:4',
            %w[J14 J20 M15 O11] => '',
          },
        }.freeze
      end
    end
  end
end
