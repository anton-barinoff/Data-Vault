import csv, hashlib
from clickhouse_driver import Client



client = Client(host='localhost', port=9000)

def md5(s):
    return hashlib.md5(s.encode('utf-8')).hexdigest()

hubs = {'loc': [], 'prod': [], 'ship': [], 'seg': []}
links, sats = [], []

with open('SampleSuperstore.csv', newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        loc_key = f"{row['City']}|{row['State']}|{row['Postal Code']}|{row['Country']}|{row['Region']}"
        prod_key = f"{row['Category']}|{row['Sub-Category']}"
        ship_key = row['Ship Mode']
        seg_key = row['Segment']

        h_loc, h_prod, h_ship, h_seg = md5(loc_key), md5(prod_key), md5(ship_key), md5(seg_key)
        h_link = md5(h_loc + h_prod + h_ship + h_seg)
        h_diff = md5(f"{row['Sales']}|{row['Quantity']}|{row['Discount']}|{row['Profit']}")

        hubs['loc'].append((h_loc, row['City'], row['State'], row['Postal Code'], row['Country'], row['Region']))
        hubs['prod'].append((h_prod, row['Category'], row['Sub-Category']))
        hubs['ship'].append((h_ship, ship_key))
        hubs['seg'].append((h_seg, seg_key))
        links.append((h_link, h_loc, h_prod, h_ship, h_seg))
        sats.append((h_link, h_diff, float(row['Sales']), int(row['Quantity']),
                     float(row['Discount']), float(row['Profit'])))

client.execute('INSERT INTO dv.hub_customer_location (hub_customer_location_hk, city, state, postal_code, country, region) VALUES',
               list(dict.fromkeys(hubs['loc'])))
client.execute('INSERT INTO dv.hub_product (hub_product_hk, category, sub_category) VALUES',
               list(dict.fromkeys(hubs['prod'])))
client.execute('INSERT INTO dv.hub_ship_mode (hub_ship_mode_hk, ship_mode) VALUES',
               list(dict.fromkeys(hubs['ship'])))
client.execute('INSERT INTO dv.hub_segment (hub_segment_hk, segment) VALUES',
               list(dict.fromkeys(hubs['seg'])))
client.execute('INSERT INTO dv.link_sale (link_sale_hk, hub_customer_location_hk, hub_product_hk, hub_ship_mode_hk, hub_segment_hk) VALUES',
               list(dict.fromkeys(links)))
client.execute('INSERT INTO dv.sat_sale_measures (link_sale_hk, hash_diff, sales, quantity, discount, profit) VALUES', sats)

print('Downloaded:', len(links), 'rows')