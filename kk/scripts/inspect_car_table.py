import sqlite3
import json

def main():
	con = sqlite3.connect('kk/instance/car_listings_dev.db')
	rows = con.execute('PRAGMA table_info(car)').fetchall()
	# rows: cid, name, type, notnull, dflt_value, pk
	print(json.dumps([{'cid':r[0],'name':r[1],'type':r[2],'notnull':r[3],'default':r[4],'pk':r[5]} for r in rows], indent=2))

if __name__ == '__main__':
	main()


